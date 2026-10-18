'use strict';

// International dialling codes for the countries a school can pick (keep in
// step with lib/core/regional/country.dart). Used to turn a national-format
// mobile number into E.164 for a school in that country.
const DIAL_CODES = {
  IN: '91', US: '1', GB: '44', IE: '353', AE: '971', SA: '966', QA: '974', KW: '965', BH: '973', OM: '968',
  JO: '962', EG: '20', SG: '65', MY: '60', ID: '62', PH: '63', TH: '66', VN: '84', BD: '880', LK: '94',
  NP: '977', PK: '92', JP: '81', KR: '82', CN: '86', AU: '61', NZ: '64', CA: '1', MX: '52', BR: '55',
  ZA: '27', NG: '234', KE: '254', GH: '233', UG: '256', TZ: '255', RW: '250', SN: '221', DE: '49',
  FR: '33', ES: '34', IT: '39', NL: '31', CH: '41',
};

/** The dialling code for an ISO country code, or [fallback] when unknown. */
function dialCodeFor(countryCode, fallback = process.env.DEFAULT_PHONE_COUNTRY_CODE || '91') {
  return DIAL_CODES[String(countryCode || '').toUpperCase()] || fallback;
}

module.exports = { DIAL_CODES, dialCodeFor };
