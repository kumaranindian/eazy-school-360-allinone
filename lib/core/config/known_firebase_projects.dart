/// The Firebase projects of this repository, by environment, and the
/// application identifier registered in each of them.
///
/// These are identifiers (not credentials). They exist so the startup
/// validation can refuse an obvious mix-up — e.g. a production build that
/// resolves the development project — independently of the option files
/// being validated. A test checks they agree with those option files.
const String kApplicationId = 'com.avail404.eazyschool.eazyschool360';

const String kDevFirebaseProjectId = 'eazy-school-360-dev';
const String kProdFirebaseProjectId = 'eazy-school-360-prod';
