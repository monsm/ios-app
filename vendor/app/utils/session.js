// cmd 01 会话令牌生命周期 (固件: 令牌 45 秒有效期, TX+0x38=0x2D; R3: 安全类型硬编码=2 Token)
// 响应 KLV 布局 (kernel/protocol 注释): #1=安全类型(bit1=1→Token) #2=token(hex) #3=有效期秒(u16 LE)
const TOKEN_TTL_MS = 45000;

class LockSession {
  constructor() {
    this.tokenHex = null;
    this.securityType = null;
    this.ttlMs = TOKEN_TTL_MS;
    this.expiresAtMs = 0;
  }
  parseTokenResponse(klvs) {
    for (const k of klvs || []) {
      if (k.key === 0x01) this.securityType = parseInt(k.val.substr(0, 2), 16) & 0x03; // 报告 §4.2.5: val[0]&0x03, ==2=Token
      else if (k.key === 0x02) this.tokenHex = k.val;
      else if (k.key === 0x03 && k.vlen >= 2) {
        const ttl = parseInt(k.val.substr(0, 2), 16) | (parseInt(k.val.substr(2, 2), 16) << 8);
        if (ttl > 0) this.ttlMs = ttl * 1000;
      }
    }
    this.expiresAtMs = Date.now() + this.ttlMs;
    return this.tokenHex;
  }
  isFresh() {
    // V80 (F3): Java isExpire() = now + 2s > expire → 剩余 <2s 即视为过期, 提前一轮预刷令牌
    return !!this.tokenHex && (this.expiresAtMs - Date.now()) > 2000;
  }
  refresh() {
    this.tokenHex = null;
    this.expiresAtMs = 0;
  }
}
module.exports = { LockSession, TOKEN_TTL_MS };
