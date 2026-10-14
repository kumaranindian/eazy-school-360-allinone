'use strict';

// Delivery of one-time codes through the Meta WhatsApp Business Platform
// (Cloud API). WhatsApp is ONLY the delivery channel: generation, storage and
// verification of the code live in otp.js.
//
// Nothing here is hard-coded to an account: the phone-number id, template name
// and language come from configuration (see docs/authentication-access-management.md),
// the access token from Secret Manager. The template must be an approved
// AUTHENTICATION-category template whose body takes the code as {{1}}.

const GRAPH = 'https://graph.facebook.com';
const TIMEOUT_MS = 8000;

class WhatsAppError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function isConfigured(cfg) {
  return !!(cfg && cfg.accessToken && cfg.phoneNumberId && cfg.templateName);
}

// Documented Cloud API error codes (verify against the current Meta docs when
// upgrading apiVersion): 131026 message undeliverable / not a WhatsApp number,
// 131030 recipient not in the allowed list (sandbox), 130429 / 80007 rate
// limit, 190 access token invalid or expired, 132000-132999 template problems.
function classify(status, body) {
  const code = body && body.error && body.error.code;
  if (code === 131026 || code === 131030 || code === 131021) return 'INVALID_RECIPIENT';
  if (code === 130429 || code === 80007 || code === 131056 || status === 429) return 'PROVIDER_RATE_LIMIT';
  if (code === 190 || status === 401) return 'PROVIDER_AUTH';
  if (typeof code === 'number' && code >= 132000 && code < 133000) return 'TEMPLATE_ERROR';
  return 'PROVIDER_ERROR';
}

function createWhatsAppSender(cfg, fetchImpl = globalThis.fetch) {
  return {
    configured: isConfigured(cfg),
    /** Sends [code] to [to] (E.164). Throws WhatsAppError; never logs the code. */
    async sendOtp({ to, code }) {
      if (!isConfigured(cfg)) throw new WhatsAppError('NOT_CONFIGURED', 'WhatsApp is not configured');
      const components = [{ type: 'body', parameters: [{ type: 'text', text: code }] }];
      // Authentication templates with a copy-code / one-tap button also
      // require the code as the button parameter.
      if (cfg.templateHasButton !== false) {
        components.push({ type: 'button', sub_type: 'url', index: '0', parameters: [{ type: 'text', text: code }] });
      }
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), cfg.timeoutMs || TIMEOUT_MS);
      let res;
      try {
        res = await fetchImpl(`${GRAPH}/${cfg.apiVersion || 'v21.0'}/${cfg.phoneNumberId}/messages`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${cfg.accessToken}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            messaging_product: 'whatsapp',
            to: to.replace(/^\+/, ''),
            type: 'template',
            template: { name: cfg.templateName, language: { code: cfg.languageCode || 'en' }, components },
          }),
          signal: ctrl.signal,
        });
      } catch (e) {
        throw new WhatsAppError(e.name === 'AbortError' ? 'TIMEOUT' : 'NETWORK', 'WhatsApp request failed');
      } finally {
        clearTimeout(timer);
      }
      if (!res.ok) {
        let body = null;
        try {
          body = await res.json();
        } catch (_) {
          /* ignore */
        }
        throw new WhatsAppError(classify(res.status, body), `WhatsApp responded ${res.status}`);
      }
    },
  };
}

module.exports = { createWhatsAppSender, WhatsAppError, isConfigured };
