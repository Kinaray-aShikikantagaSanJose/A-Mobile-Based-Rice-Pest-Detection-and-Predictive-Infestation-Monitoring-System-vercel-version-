// Messages the API sends (they stay English on the server and are translated
// here when shown). Key = the exact English message.
// Each entry: { fil: 'Filipino', krj: 'Kinaray-a (Antique)' }. Keep {placeholders} unchanged.
export default {
  'Not authenticated.': { fil: 'Hindi naka-log in.', krj: 'Indi naka-log in.' },
  'Session expired. Please log in again.': { fil: 'Nag-expire ang session. Mag-log in ulit.', krj: 'Nag-expire ang session. Mag-log in liwan.' },
  'Account not found. Please log in again.': { fil: 'Hindi makita ang account. Mag-log in ulit.', krj: 'Indi makita ang account. Mag-log in liwan.' },
  'Insufficient role.': { fil: 'Hindi pwede sa iyong tungkulin.', krj: 'Indi pwede sa imo nga role.' },
  "Your account doesn't have access to this.": { fil: 'Walang access ang iyong account dito.', krj: 'Wara it access ang imo nga account diya.' },
  'Invalid email or password.': { fil: 'Mali ang email o password.', krj: 'Sala ang email ukon password.' },
  'Please verify your email before logging in.': {
    fil: 'I-verify muna ang iyong email bago mag-log in.',
    krj: 'I-verify anay ang imo nga email antes mag-log in.',
  },
  'Observation not found.': { fil: 'Hindi makita ang obserbasyon.', krj: 'Indi makita ang obserbasyon.' },
  'This observation was deleted.': { fil: 'Nabura na ang obserbasyong ito.', krj: 'Napanas run ang obserbasyon nga kadya.' },
  "You can't delete this observation.": { fil: 'Hindi mo pwedeng burahin ang obserbasyong ito.', krj: 'Indi mo pwede panason ang obserbasyon nga kadya.' },
  "Your role can't delete records.": { fil: 'Hindi pwedeng magbura ng rekord ang iyong tungkulin.', krj: 'Indi pwede magpanas it rekord ang imo nga role.' },
  'This observation has already been handled.': { fil: 'Naasikaso na ang obserbasyong ito.', krj: 'Naasikaso run ang obserbasyon nga kadya.' },
  'Activity logs need a database update first (supabase/01_schema.sql, section 2026-11).': {
    fil: 'Kailangan munang i-update ang database para sa talaan ng aktibidad (supabase/01_schema.sql, bahaging 2026-11).',
    krj: 'Kinahanglan anay i-update ang database para sa listahan it aktibidad (supabase/01_schema.sql, parte 2026-11).',
  },
  'The server took too long to respond. Check your connection and try again.': {
    fil: 'Masyadong natagalan ang server. Tingnan ang iyong internet at subukan ulit.',
    krj: 'Madugay gid ang server. Turuka ang imo nga internet kag tilawan liwan.',
  },
  'Too many attempts. Please wait a moment and try again.': {
    fil: 'Masyadong maraming subok. Maghintay sandali at subukan ulit.',
    krj: 'Madamo gid ang tilaw. Maghulat anay kag tilawan liwan.',
  },
  'The server sent a response the dashboard could not read.': {
    fil: 'Nagpadala ang server ng sagot na hindi mabasa ng dashboard.',
    krj: 'Nagpadara ang server it sabat nga indi mabasa it dashboard.',
  },
  'An account with this email already exists.': { fil: 'May account na sa email na ito.', krj: 'May account run sa email nga kadya.' },
  'Account not found.': { fil: 'Hindi makita ang account.', krj: 'Indi makita ang account.' },
  "You can't delete your own account.": { fil: 'Hindi mo pwedeng burahin ang sarili mong account.', krj: 'Indi mo pwede panason ang imo kaugalingon nga account.' },
  "You can't change your own role or approval.": {
    fil: 'Hindi mo pwedeng palitan ang sarili mong tungkulin o approval.',
    krj: 'Indi mo pwede bayluhan ang imo kaugalingon nga role ukon approval.',
  },
  "This person hasn't verified their email yet.": { fil: 'Hindi pa na-verify ng taong ito ang email.', krj: 'Indi pa na-verify it tawo nga kadya ang email.' },
  'Recommendation not found.': { fil: 'Hindi makita ang rekomendasyon.', krj: 'Indi makita ang rekomendasyon.' },
  'Treatment not found.': { fil: 'Hindi makita ang lunas.', krj: 'Indi makita ang bulong.' },
  'The photo was removed because no pests were found.': {
    fil: 'Inalis ang litrato dahil walang nakitang peste.',
    krj: 'Ginkuha ang litrato kay wara it nakita nga peste.',
  },

  // ---- model results (app/detector.py)
  'No pests were found in this photo.': { fil: 'Walang nakitang peste sa litratong ito.', krj: 'Wara it nakita nga peste sa litrato nga kadya.' },
  'Automatic analysis is unavailable. A technician will identify the pest.': {
    fil: 'Hindi magamit ang awtomatikong pagsusuri. Ang technician ang tutukoy sa peste.',
    krj: 'Indi magamit ang awtomatiko nga pag-usisa. Ang technician ang mangilala sa peste.',
  },
  'No supported pest was recognized with confidence. A technician will check the photo.': {
    fil: 'Walang suportadong peste na tiyak na nakilala. Titingnan ng technician ang litrato.',
    krj: 'Wara it suportado nga peste nga sigurado nga nakilala. Turukon it technician ang litrato.',
  },
  'Possible pests were found, but not clearly enough to name one. A technician will identify it.': {
    fil: 'May posibleng peste, pero hindi malinaw para matukoy. Ang technician ang tutukoy nito.',
    krj: 'May posible nga peste, pero indi malinaw para makilala. Ang technician ang mangilala.',
  },
  'Other pests may also be in the photo; the technician will check.': {
    fil: 'Baka may iba pang peste sa litrato; titingnan ng technician.',
    krj: 'Basi may iban pa nga peste sa litrato; turukon it technician.',
  },
  'The insects are too close together to count reliably.': {
    fil: 'Masyadong magkakadikit ang mga insekto para mabilang nang tama.',
    krj: 'Masyado magkadikit ang mga insekto para maisip it husto.',
  },
  'The insects are not clear enough to count reliably.': {
    fil: 'Hindi sapat na malinaw ang mga insekto para mabilang nang tama.',
    krj: 'Indi malinaw gid ang mga insekto para maisip it husto.',
  },
  'The photo looks blurry; the technician may ask for a new one.': {
    fil: 'Mukhang malabo ang litrato; baka humingi ng bago ang technician.',
    krj: 'Daw malabo ang litrato; basi mangayo it bag-o ang technician.',
  },
  'The photo looks too dark; the technician may ask for a new one.': {
    fil: 'Mukhang masyadong madilim ang litrato; baka humingi ng bago ang technician.',
    krj: 'Daw madulom gid ang litrato; basi mangayo it bag-o ang technician.',
  },
  'The photo looks washed out by light; the technician may ask for a new one.': {
    fil: 'Mukhang sobrang liwanag ang litrato; baka humingi ng bago ang technician.',
    krj: 'Daw sobra kasanag ang litrato; basi mangayo it bag-o ang technician.',
  },
  'Chemical control is a last resort. Talk to your agricultural technician or municipal agriculture office before using any pesticide, and always follow the label.': {
    fil: 'Huling paraan ang kemikal. Kausapin muna ang iyong technician o municipal agriculture office bago gumamit ng pestisidyo, at laging sundin ang label.',
    krj: 'Katapusan nga paagi ang kemikal. Hambali anay ang imo nga technician ukon municipal agriculture office antes maggamit it pestisidyo, kag permi sundon ang label.',
  },
};
