// wx 存储安全封装 — node 单测环境降级为进程内 Map (不再静默丢弃, 钥匙串/台账流程可测)
function _mem() {
  if (typeof globalThis.__kf_mem_store === 'undefined') globalThis.__kf_mem_store = {};
  return globalThis.__kf_mem_store;
}
function get(key, def) {
  try {
    if (typeof wx !== 'undefined' && wx.getStorageSync) {
      const v = wx.getStorageSync(key);
      if (v === '' || v === undefined || v === null) return def;
      return v;
    }
  } catch (e) {}
  const m = _mem();
  return key in m ? m[key] : def;
}
function set(key, val) {
  try {
    if (typeof wx !== 'undefined' && wx.setStorageSync) { wx.setStorageSync(key, val); return; }
  } catch (e) {}
  _mem()[key] = val;
}
function remove(key) {
  try {
    if (typeof wx !== 'undefined' && wx.removeStorageSync) { wx.removeStorageSync(key); return; }
  } catch (e) {}
  delete _mem()[key];
}
// 枚举全部存储键 (schema 迁移按前缀扫 mac 族键用; wx 需基础库支持 getStorageInfoSync)
function keys() {
  try {
    if (typeof wx !== 'undefined' && wx.getStorageInfoSync) {
      const info = wx.getStorageInfoSync();
      if (info && Array.isArray(info.keys)) return info.keys;
    }
  } catch (e) {}
  return Object.keys(_mem());
}
module.exports = { get, set, remove, keys };
