/*
  Plug Electronics & More — Supabase adapter
  Copyright (c) 2026 M&P Developers. All rights reserved. Licensed to Plug Electronics & More.

  Gives the site the same small data API it used on claude.ai (claude.use('db' | 'user' | 'assets' | 'downloads')),
  backed by Supabase. If config.js has no Supabase keys, nothing is defined and the site runs in
  stand-alone mode (built-in catalogue, WhatsApp ordering, admin demo saved on the device).
*/
(function () {
  var CFG = window.PLUG_CONFIG || {};
  if (!CFG.supabaseUrl || !CFG.supabaseKey || !window.supabase || !window.supabase.createClient) return;

  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseKey, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: 'plug-auth' }
  });
  var BUCKET = CFG.imageBucket || 'product-images';

  /* ---------------- session / roles ---------------- */
  var sessionP = sb.auth.getSession().then(function (r) { return (r && r.data && r.data.session) || null; }).catch(function () { return null; });
  var roleP = sessionP.then(function (s) {
    if (!s || !s.user || s.user.is_anonymous) return { admin: false, owner: false, name: '' };
    return sb.from('admins').select('owner,name').eq('user_id', s.user.id).maybeSingle().then(function (r) {
      var d = r && r.data;
      return { admin: !!d, owner: !!(d && d.owner), name: (d && d.name) || s.user.email || '' };
    }).catch(function () { return { admin: false, owner: false, name: '' }; });
  });
  // Visitors only get an (anonymous) identity when they actually place an order or subscribe.
  var anonP = null;
  function ensureUid() {
    return sessionP.then(function (s) {
      if (s && s.user) return s.user.id;
      if (!anonP) anonP = sb.auth.signInAnonymously().then(function (r) {
        var ns = r && r.data && r.data.session; if (ns) { sessionP = Promise.resolve(ns); return ns.user.id; } return null;
      }).catch(function () { return null; });
      return anonP;
    });
  }
  window.PLUG_ENSURE_UID = ensureUid;

  /* ---------------- documents ---------------- */
  // Everything lives in one table: docs(collection, id, data jsonb, owner, updated_at)
  function split(path) { var i = path.indexOf('/'); return [path.slice(0, i), path.slice(i + 1)]; }
  function docSnap(row) { return { id: row ? row.id : null, exists: !!row, data: function () { return row ? row.data : undefined; } }; }
  function colSnap(rows) { return { docs: rows.map(function (r) { return { id: r.id, exists: true, data: function () { return r.data; } }; }), size: rows.length }; }
  function fail(r) { if (r && r.error) { var e = new Error(r.error.message || 'Database error'); e.code = r.error.code; throw e; } return r; }

  var cache = {};      // collection -> rows
  var subs = {};       // collection -> [fn]
  var errs = {};       // collection -> [fn]
  var timers = {};
  function load(col) {
    return sb.from('docs').select('id,data').eq('collection', col).then(function (r) {
      if (r.error) { (errs[col] || []).forEach(function (f) { try { f(r.error); } catch (e) {} }); return; }
      cache[col] = r.data || [];
      (subs[col] || []).forEach(function (f) { try { f(cache[col]); } catch (e) {} });
    });
  }
  function refreshSoon(col) { clearTimeout(timers[col]); timers[col] = setTimeout(function () { load(col); }, 120); }
  function listen(col, fn, onErr) {
    (subs[col] = subs[col] || []).push(fn); if (onErr) (errs[col] = errs[col] || []).push(onErr);
    if (cache[col]) fn(cache[col]); else load(col);
    return function () { subs[col] = (subs[col] || []).filter(function (x) { return x !== fn; }); };
  }
  // live updates (falls back to a slow poll if realtime is unavailable)
  try {
    sb.channel('plug-docs').on('postgres_changes', { event: '*', schema: 'public', table: 'docs' }, function (p) {
      var row = p.new && p.new.collection ? p.new : p.old; if (row && row.collection) refreshSoon(row.collection);
    }).subscribe();
  } catch (e) {}
  setInterval(function () { if (!document.hidden) Object.keys(subs).forEach(function (c) { if ((subs[c] || []).length) load(c); }); }, 60000);

  var db = {
    doc: function (path) {
      var p = split(path), col = p[0], id = p[1];
      return {
        get: function () { return sb.from('docs').select('id,data').eq('collection', col).eq('id', id).maybeSingle().then(fail).then(function (r) { return docSnap(r.data); }); },
        set: function (data) {
          return ensureUid().then(function (uid) {
            return sb.from('docs').upsert({ collection: col, id: id, data: data, owner: uid || null, updated_at: new Date().toISOString() }, { onConflict: 'collection,id' });
          }).then(fail).then(function () { refreshSoon(col); });
        },
        delete: function () { return sb.from('docs').delete().eq('collection', col).eq('id', id).then(fail).then(function () { refreshSoon(col); }); },
        onSnapshot: function (fn, onErr) { return listen(col, function (rows) { fn(docSnap(rows.filter(function (r) { return r.id === id; })[0])); }, onErr); }
      };
    },
    collection: function (col) {
      return {
        get: function () { return sb.from('docs').select('id,data').eq('collection', col).then(fail).then(function (r) { return colSnap(r.data || []); }); },
        onSnapshot: function (fn, onErr) { return listen(col, function (rows) { fn(colSnap(rows)); }, onErr); }
      };
    }
  };

  /* ---------------- user ---------------- */
  var user = {
    canEdit: function () { return roleP.then(function (r) { return r.admin; }); },
    isOwner: function () { return roleP.then(function (r) { return r.owner; }); },
    id: function () { return sessionP.then(function (s) { return s && s.user ? s.user.id : null; }); },
    me: function () { return roleP.then(function (r) { return { name: r.name }; }); }
  };

  /* ---------------- images ---------------- */
  var assets = {
    upload: function (blob) {
      var ext = ((blob.type || 'image/webp').split('/')[1] || 'webp').replace('jpeg', 'jpg');
      var name = 'p/' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7) + '.' + ext;
      return sb.storage.from(BUCKET).upload(name, blob, { contentType: blob.type || 'image/webp', upsert: false }).then(fail).then(function () {
        return { url: sb.storage.from(BUCKET).getPublicUrl(name).data.publicUrl };
      });
    }
  };

  /* ---------------- downloads ---------------- */
  var downloads = {
    save: function (o) {
      var b = new Blob([o.data], { type: /\.csv$/i.test(o.filename) ? 'text/csv' : 'text/plain' });
      var a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = o.filename || 'download.txt';
      document.body.appendChild(a); a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
      return Promise.resolve();
    }
  };

  window.claude = { use: function (name) { return Promise.resolve({ db: db, user: user, assets: assets, downloads: downloads }[name] || null); } };

  /* ---------------- staff sign-in (admin page) ---------------- */
  window.PLUG_AUTH = {
    signIn: function (email, password) { return sb.auth.signInWithPassword({ email: email, password: password }).then(fail); },
    signOut: function () { return sb.auth.signOut(); },
    reset: function (email) { return sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname }).then(fail); },
    session: function () { return sessionP; }
  };
})();
