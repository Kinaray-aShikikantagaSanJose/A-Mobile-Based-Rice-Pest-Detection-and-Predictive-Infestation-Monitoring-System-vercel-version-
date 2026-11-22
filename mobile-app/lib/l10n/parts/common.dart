// Translations (common: navigation, account, shared helpers and labels).
// Key = the English text used in the code.
// Each entry: {'fil': 'Filipino', 'krj': 'Kinaray-a (Antique)'}. Keep {placeholders} unchanged.
const Map<String, Map<String, String>> kCommonStrings = {
  // ---- bottom navigation
  'Home': {'fil': 'Home', 'krj': 'Home'},
  'Records': {'fil': 'Mga rekord', 'krj': 'Mga rekord'},
  'Treatments': {'fil': 'Mga lunas', 'krj': 'Mga bulong'},
  'Alerts': {'fil': 'Mga abiso', 'krj': 'Mga pahibaro'},
  'Queue': {'fil': 'Pila', 'krj': 'Pila'},
  'Map': {'fil': 'Mapa', 'krj': 'Mapa'},
  'Scan': {'fil': 'I-scan', 'krj': 'I-scan'},
  'New observation': {'fil': 'Bagong obserbasyon', 'krj': 'Bag-o nga obserbasyon'},

  // ---- language
  'Language': {'fil': 'Wika', 'krj': 'Lengguahe'},
  'Choose your language': {'fil': 'Piliin ang iyong wika', 'krj': 'Pilia ang imo nga lengguahe'},
  'Change': {'fil': 'Palitan', 'krj': 'Bayluhan'},

  // ---- account sheet
  'Account': {'fil': 'Account', 'krj': 'Account'},
  'Agricultural technician': {'fil': 'Agricultural technician', 'krj': 'Agricultural technician'},
  'Agriculturist': {'fil': 'Agriculturist', 'krj': 'Agriculturist'},
  'Farmer': {'fil': 'Magsasaka', 'krj': 'Mangunguma'},
  'Checking…': {'fil': 'Tinitingnan…', 'krj': 'Ginaturuk…'},
  'Some observations are waiting for signal.': {
    'fil': 'May mga obserbasyong naghihintay ng signal.',
    'krj': 'May mga obserbasyon nga nagahulat it signal.',
  },
  'Everything is sent.': {'fil': 'Naipadala na lahat.', 'krj': 'Napadara run tanan.'},
  'Send now': {'fil': 'Ipadala na', 'krj': 'Ipadara run'},
  'Edit profile': {'fil': 'I-edit ang profile', 'krj': 'I-edit ang profile'},
  'Sign out': {'fil': 'Mag-log out', 'krj': 'Mag-log out'},
  'Mobile': {'fil': 'Mobile', 'krj': 'Mobile'},
  'Some work has not been sent': {'fil': 'May hindi pa naipapadala', 'krj': 'May wara pa napadara'},
  'You have observations or treatments that are still on this phone. They are sent when you sign in again with this account. If a different account signs in on this phone, they are deleted.': {
    'fil':
        'May mga obserbasyon o lunas ka pa sa teleponong ito. Maipapadala ang mga ito kapag nag-log in ka ulit gamit ang account na ito. Kung ibang account ang mag-log in sa teleponong ito, mabubura ang mga ito.',
    'krj':
        'May mga obserbasyon ukon bulong ka pa sa telepono nga kadya. Ipadara dya kon maglog in ka liwan gamit ang account nga kadya. Kon iban nga account ang maglog in sa telepono nga kadya, mapanas dya.',
  },
  'Stay signed in': {'fil': 'Manatiling naka-log in', 'krj': 'Magpabilin nga naka-log in'},

  // ---- record states and labels (lib/utils/formatters.dart, lib/models/record.dart)
  'Waiting for signal': {'fil': 'Naghihintay ng signal', 'krj': 'Nagahulat it signal'},
  'For technician validation': {'fil': 'Para sa validation ng technician', 'krj': 'Para sa validation it technician'},
  'Sent for review': {'fil': 'Ipinadala para suriin', 'krj': 'Ginpadara para usisaon'},
  'With an agriculturist': {'fil': 'Nasa agriculturist', 'krj': 'Yara sa agriculturist'},
  'Please send a new photo': {'fil': 'Magpadala ng bagong litrato', 'krj': 'Magpadara it bag-o nga litrato'},
  'Validated': {'fil': 'Na-validate', 'krj': 'Na-validate'},
  'No pests found': {'fil': 'Walang nakitang peste', 'krj': 'Wara it nakita nga peste'},
  'Pest report': {'fil': 'Ulat ng peste', 'krj': 'Report it peste'},
  'Disease report': {'fil': 'Ulat ng sakit', 'krj': 'Report it balatian'},
  'No supported pest recognized': {'fil': 'Walang nakilalang suportadong peste', 'krj': 'Wara it nakilala nga suportado nga peste'},
  'Not identified': {'fil': 'Hindi pa natukoy', 'krj': 'Wara pa makilala'},
  'Outside the supported pests': {'fil': 'Wala sa suportadong peste', 'krj': 'Wara sa suportado nga peste'},
  '{n}% sure': {'fil': '{n}% sigurado', 'krj': '{n}% sigurado'},
  'High': {'fil': 'Mataas', 'krj': 'Mataas'},
  'Medium': {'fil': 'Katamtaman', 'krj': 'Tunga-tunga'},
  'Low': {'fil': 'Mababa', 'krj': 'Manubo'},
  'Upland': {'fil': 'Mataas na lupa (upland)', 'krj': 'Bukid nga duta (upland)'},
  'Rainfed lowland': {'fil': 'Palayang umaasa sa ulan', 'krj': 'Uma nga gasandig sa uran'},
  'Irrigated lowland': {'fil': 'Palayang may patubig', 'krj': 'Uma nga may patubig'},
  'Not recorded': {'fil': 'Hindi naitala', 'krj': 'Wara natala'},
  'Sloping or high ground, no bunds, no standing water. Rain is the only water.': {
    'fil': 'Matarik o mataas na lupa, walang pilapil, walang nakatigil na tubig. Ulan lang ang tubig.',
    'krj': 'Bakilid ukon mataas nga duta, wara it pilapil, wara it nagatining nga tubig. Uran lang ang tubig.',
  },
  'Bunded, flat paddy that holds water from rain or run-off only.': {
    'fil': 'Patag na palayan na may pilapil; tubig-ulan o umaagos na tubig lang ang laman.',
    'krj': 'Patag nga uma nga may pilapil; tubig it uran ukon nagailig nga tubig lang ang sulod.',
  },
  'Bunded, flat paddy with water from an irrigation canal or pump.': {
    'fil': 'Patag na palayan na may pilapil; may tubig mula sa irigasyon o bomba.',
    'krj': 'Patag nga uma nga may pilapil; may tubig halin sa irigasyon ukon bomba.',
  },
  'Seedling to tillering': {'fil': 'Punla hanggang pag-uusbong', 'krj': 'Pasungay hasta pagsupang'},
  'Booting to flowering': {'fil': 'Pagbubuntis hanggang pamumulaklak', 'krj': 'Pagbusong hasta pagbulak'},
  'Grain filling to harvest': {'fil': 'Paglaman ng butil hanggang anihan', 'krj': 'Pagsulod it bugas hasta alani'},
  'Cultural': {'fil': 'Kultural', 'krj': 'Kultural'},
  'Biological': {'fil': 'Biyolohikal', 'krj': 'Biyolohikal'},
  'Ecological': {'fil': 'Ekolohikal', 'krj': 'Ekolohikal'},
  'Chemical': {'fil': 'Kemikal', 'krj': 'Kemikal'},
  'My own method': {'fil': 'Sarili kong paraan', 'krj': 'Akon kaugalingon nga paagi'},

  // ---- dates and counts
  'Today': {'fil': 'Ngayon', 'krj': 'Makaron'},
  'Yesterday': {'fil': 'Kahapon', 'krj': 'Kahapon'},
  '{n} days ago': {'fil': '{n} araw na ang nakalipas', 'krj': '{n} ka adlaw run ang nakaagi'},
  '{n} min': {'fil': '{n} min', 'krj': '{n} min'},
  '{n} h': {'fil': '{n} oras', 'krj': '{n} oras'},
  '{n} day': {'fil': '{n} araw', 'krj': '{n} adlaw'},
  '{n} days': {'fil': '{n} araw', 'krj': '{n} adlaw'},
  '{n} insect': {'fil': '{n} insekto', 'krj': '{n} ka insekto'},
  '{n} insects': {'fil': '{n} insekto', 'krj': '{n} ka insekto'},
  '{n} record': {'fil': '{n} rekord', 'krj': '{n} ka rekord'},
  '{n} records': {'fil': '{n} rekord', 'krj': '{n} ka rekord'},
  'Jan': {'fil': 'Ene', 'krj': 'Ene'},
  'Feb': {'fil': 'Peb', 'krj': 'Peb'},
  'Mar': {'fil': 'Mar', 'krj': 'Mar'},
  'Apr': {'fil': 'Abr', 'krj': 'Abr'},
  'May': {'fil': 'May', 'krj': 'May'},
  'Jun': {'fil': 'Hun', 'krj': 'Hun'},
  'Jul': {'fil': 'Hul', 'krj': 'Hul'},
  'Aug': {'fil': 'Ago', 'krj': 'Ago'},
  'Sep': {'fil': 'Set', 'krj': 'Set'},
  'Oct': {'fil': 'Okt', 'krj': 'Okt'},
  'Nov': {'fil': 'Nob', 'krj': 'Nob'},
  'Dec': {'fil': 'Dis', 'krj': 'Dis'},

  // ---- area from GPS (lib/widgets/gps_area.dart, barangay_field.dart)
  'Use my location': {'fil': 'Gamitin ang aking lokasyon', 'krj': 'Gamiton ang akon nga lokasyon'},
  'Use it': {'fil': 'Gamitin ito', 'krj': 'Gamiton dya'},
  'Try again': {'fil': 'Subukan ulit', 'krj': 'Tilawan liwan'},
  'Finding your barangay from your location…': {
    'fil': 'Hinahanap ang iyong barangay gamit ang iyong lokasyon…',
    'krj': 'Ginapangita ang imo nga barangay gamit ang imo nga lokasyon…',
  },
  'Location is turned off. Choose your municipality and barangay below, or turn on location and try again.': {
    'fil': 'Naka-off ang lokasyon. Piliin ang iyong munisipyo at barangay sa ibaba, o i-on ang lokasyon at subukan ulit.',
    'krj': 'Naka-off ang lokasyon. Pilia ang imo nga banwa kag barangay sa idalom, ukon i-on ang lokasyon kag tilawan liwan.',
  },
  'Location permission is off. Choose your municipality and barangay below.': {
    'fil': 'Hindi pinayagan ang lokasyon. Piliin ang iyong munisipyo at barangay sa ibaba.',
    'krj': 'Wara gintugutan ang lokasyon. Pilia ang imo nga banwa kag barangay sa idalom.',
  },
  'Could not get your location. Choose your municipality and barangay below.': {
    'fil': 'Hindi makuha ang iyong lokasyon. Piliin ang iyong munisipyo at barangay sa ibaba.',
    'krj': 'Indi makuha ang imo nga lokasyon. Pilia ang imo nga banwa kag barangay sa idalom.',
  },
  'You seem to be outside Antique. Choose your municipality and barangay below.': {
    'fil': 'Mukhang nasa labas ka ng Antique. Piliin ang iyong munisipyo at barangay sa ibaba.',
    'krj': 'Daw yara ka sa guwa it Antique. Pilia ang imo nga banwa kag barangay sa idalom.',
  },
  'Filled in from GPS: {place}. Please check it.': {
    'fil': 'Nilagay mula sa GPS: {place}. Pakitingnan kung tama.',
    'krj': 'Ginbutang halin sa GPS: {place}. Palihog turuka kon husto.',
  },
  'Your GPS is not accurate yet (about {n} m), so this may be wrong: {place}.': {
    'fil': 'Hindi pa tumpak ang GPS (mga {n} m), kaya baka mali ito: {place}.',
    'krj': 'Indi pa husto ang GPS (mga {n} m), gani basi sala dya: {place}.',
  },
  'Found from GPS: {place}. Change it below if this is not where you farm.': {
    'fil': 'Nakita sa GPS: {place}. Palitan sa ibaba kung hindi dito ang iyong sakahan.',
    'krj': 'Nakita sa GPS: {place}. Bayluhan sa idalom kon bukon diya ang imo nga uma.',
  },
  'GPS shows {place}. Your saved area was kept.': {
    'fil': 'Ipinapakita ng GPS ang {place}. Hindi binago ang naka-save mong lugar.',
    'krj': 'Ginapakita it GPS ang {place}. Wara ginbag-o ang naka-save mo nga lugar.',
  },
  'You are near a barangay boundary, so please check it.': {
    'fil': 'Malapit ka sa hangganan ng barangay, kaya pakitingnan ito.',
    'krj': 'Malapit ka sa utod it barangay, gani palihog turuka.',
  },
  'Type to see the barangays of {municipality}.': {
    'fil': 'Mag-type para makita ang mga barangay ng {municipality}.',
    'krj': 'Mag-type para makita ang mga barangay it {municipality}.',
  },
};
