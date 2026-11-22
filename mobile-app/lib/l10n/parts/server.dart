// Messages from the server and the connection layer. They stay English in
// the code and on the server and are translated here when shown
// (`context.tr(e.message)`). Key = the exact English message.
// Each entry: {'fil': 'Filipino', 'krj': 'Kinaray-a (Antique)'}. Keep {placeholders} unchanged.
const Map<String, Map<String, String>> kServerStrings = {
  // ---- connection (lib/services/api_client.dart)
  "Can't find the Palay Patrol server. Connect this device to the same Wi-Fi, Ethernet, or hotspot network as the server.": {
    'fil': 'Hindi makita ang Palay Patrol server. Ikonekta ang device sa parehong Wi-Fi, Ethernet o hotspot ng server.',
    'krj': 'Indi makita ang Palay Patrol server. Ikonekta ang device sa pareho nga Wi-Fi, Ethernet ukon hotspot it server.',
  },
  'No connection to the server right now.': {'fil': 'Walang koneksyon sa server ngayon.', 'krj': 'Wara it koneksyon sa server makaron.'},
  'The server took too long to answer. Check your signal and try again.': {
    'fil': 'Masyadong natagalan ang server. Tingnan ang signal at subukan ulit.',
    'krj': 'Madugay gid ang server. Turuka ang signal kag tilawan liwan.',
  },
  'Your session ended. Please sign in again.': {'fil': 'Natapos ang iyong session. Mag-log in ulit.', 'krj': 'Natapos ang imo nga session. Mag-log in liwan.'},
  'Please sign in again.': {'fil': 'Mag-log in ulit.', 'krj': 'Mag-log in liwan.'},
  'Too many attempts. Please wait a moment and try again.': {
    'fil': 'Masyadong maraming subok. Maghintay sandali at subukan ulit.',
    'krj': 'Madamo gid ang tilaw. Maghulat anay kag tilawan liwan.',
  },

  // ---- sign-in, account
  'Session expired. Please log in again.': {'fil': 'Nag-expire ang session. Mag-log in ulit.', 'krj': 'Nag-expire ang session. Mag-log in liwan.'},
  'Account not found. Please log in again.': {'fil': 'Hindi makita ang account. Mag-log in ulit.', 'krj': 'Indi makita ang account. Mag-log in liwan.'},
  'Insufficient role.': {'fil': 'Hindi pwede sa iyong tungkulin.', 'krj': 'Indi pwede sa imo nga role.'},
  'Email is already registered.': {'fil': 'Nakarehistro na ang email na ito.', 'krj': 'Nakarehistro run ang email nga kadya.'},
  'User account not found.': {'fil': 'Hindi makita ang account.', 'krj': 'Indi makita ang account.'},
  'Account is already verified.': {'fil': 'Na-verify na ang account.', 'krj': 'Na-verify run ang account.'},
  'Your account is waiting for approval by an agriculturist.': {
    'fil': 'Naghihintay pa ng approval ng agriculturist ang iyong account.',
    'krj': 'Nagahulat pa it approval it agriculturist ang imo nga account.',
  },
  'Your account was not approved.': {'fil': 'Hindi naaprubahan ang iyong account.', 'krj': 'Indi naaprubahan ang imo nga account.'},
  'Your municipality sets your coverage area. Ask an agriculturist to change it.': {
    'fil': 'Ang iyong munisipyo ang nagtatakda ng iyong sakop. Pakiusapan ang agriculturist na palitan ito.',
    'krj': 'Ang imo nga banwa ang nagabutang it imo nga sakop. Pangabaya ang agriculturist nga bayluhan dya.',
  },
  'Your current password is not correct.': {'fil': 'Mali ang kasalukuyan mong password.', 'krj': 'Sala ang password mo makaron.'},
  'That picture is too large (8 MB at most).': {'fil': 'Masyadong malaki ang larawan (8 MB lang ang pinakamalaki).', 'krj': 'Dako gid ang litrato (8 MB lang ang pinakadako).'},
  "That file isn't a picture. Choose a JPG or PNG photo.": {
    'fil': 'Hindi larawan ang file na iyan. Pumili ng JPG o PNG.',
    'krj': 'Bukon litrato ang file nga ina. Mamili it JPG ukon PNG.',
  },
  'The picture could not be stored right now. Please try again.': {
    'fil': 'Hindi ma-save ang larawan ngayon. Pakisubukan ulit.',
    'krj': 'Indi ma-save ang litrato makaron. Palihog tilawan liwan.',
  },

  // ---- observations
  'Choose the land type: upland, rainfed lowland or irrigated lowland.': {
    'fil': 'Piliin ang uri ng lupa: upland, umaasa sa ulan, o may patubig.',
    'krj': 'Pilia ang klase it duta: upland, gasandig sa uran, ukon may patubig.',
  },
  'Describe what you observed for a disease report.': {
    'fil': 'Ilarawan ang iyong nakita para sa ulat ng sakit.',
    'krj': 'Laragway ang imo nakita para sa report it balatian.',
  },
  'Invalid location.': {'fil': 'Mali ang lokasyon.', 'krj': 'Sala ang lokasyon.'},
  'Photo is too large (15 MB at most).': {'fil': 'Masyadong malaki ang litrato (15 MB lang ang pinakamalaki).', 'krj': 'Dako gid ang litrato (15 MB lang ang pinakadako).'},
  'The photo could not be read. Please retake it.': {'fil': 'Hindi mabasa ang litrato. Pakikuha ulit.', 'krj': 'Indi mabasa ang litrato. Palihog kuhaan liwan.'},
  'The photo could not be stored right now. Please try again.': {
    'fil': 'Hindi ma-save ang litrato ngayon. Pakisubukan ulit.',
    'krj': 'Indi ma-save ang litrato makaron. Palihog tilawan liwan.',
  },
  'The observation could not be saved. Please try again.': {
    'fil': 'Hindi ma-save ang obserbasyon. Pakisubukan ulit.',
    'krj': 'Indi ma-save ang obserbasyon. Palihog tilawan liwan.',
  },
  'Observation not found.': {'fil': 'Hindi makita ang obserbasyon.', 'krj': 'Indi makita ang obserbasyon.'},
  'This observation was deleted.': {'fil': 'Nabura na ang obserbasyong ito.', 'krj': 'Napanas run ang obserbasyon nga kadya.'},
  "You can't delete this observation.": {'fil': 'Hindi mo pwedeng burahin ang obserbasyong ito.', 'krj': 'Indi mo pwede panason ang obserbasyon nga kadya.'},
  "Your role can't delete records.": {'fil': 'Hindi pwedeng magbura ng rekord ang iyong tungkulin.', 'krj': 'Indi pwede magpanas it rekord ang imo nga role.'},
  'This observation has already been handled.': {'fil': 'Naasikaso na ang obserbasyong ito.', 'krj': 'Naasikaso run ang obserbasyon nga kadya.'},
  'The photo was removed because no pests were found.': {
    'fil': 'Inalis ang litrato dahil walang nakitang peste.',
    'krj': 'Ginkuha ang litrato kay wara it nakita nga peste.',
  },
  'Treatments can be logged once a pest observation is validated.': {
    'fil': 'Maitatala ang lunas kapag na-validate na ang obserbasyon ng peste.',
    'krj': 'Matala ang bulong kon na-validate run ang obserbasyon it peste.',
  },
  "The date can't be in the future.": {'fil': 'Hindi pwedeng nasa hinaharap ang petsa.', 'krj': 'Indi pwede nga sa palaabuton ang petsa.'},
  'That option is no longer in the approved list.': {
    'fil': 'Wala na sa aprubadong listahan ang opsyong iyan.',
    'krj': 'Wara run sa aprubado nga listahan ang opsyon nga ina.',
  },
  'Pick an option or describe what you did.': {'fil': 'Pumili ng opsyon o ilarawan ang iyong ginawa.', 'krj': 'Mamili it opsyon ukon laragway ang imo ginhimo.'},

  // ---- review (technicians)
  'Tell the farmer why (e.g. photo too blurry).': {
    'fil': 'Sabihin sa magsasaka kung bakit (hal. malabo ang litrato).',
    'krj': 'Sugiri ang mangunguma kon ham-at (pananglitan malabo ang litrato).',
  },
  'Say why it needs an agriculturist.': {'fil': 'Sabihin kung bakit kailangan ng agriculturist.', 'krj': 'Sugiri kon ham-at kinahanglan it agriculturist.'},
  'Confirm the infestation level.': {'fil': 'Kumpirmahin ang antas ng peste.', 'krj': 'Kumpirmaha ang lebel it peste.'},
  'Record the diagnosis and the guidance for the farmer.': {
    'fil': 'Itala ang diagnosis at payo para sa magsasaka.',
    'krj': 'Itala ang diagnosis kag tugon para sa mangunguma.',
  },
  'Enter the count, or mark it not countable.': {
    'fil': 'Ilagay ang bilang, o markahang hindi mabilang.',
    'krj': 'Ibutang ang isip, ukon markahan nga indi maisip.',
  },
  "Pick one of the four pests, or 'outside the supported set'.": {
    'fil': "Pumili ng isa sa apat na peste, o 'wala sa suportado'.",
    'krj': "Mamili it isa sa apat nga peste, ukon 'wara sa suportado'.",
  },
  "Agriculturists resolve escalations; they can't escalate.": {
    'fil': 'Ang agriculturist ang nag-aayos ng ipinasang kaso; hindi sila nagpapasa.',
    'krj': 'Ang agriculturist ang gausisa it ginpasa nga kaso; indi sanda gapasa.',
  },

  // ---- model results (app/detector.py), shown with each pest report
  'No pests were found in this photo.': {'fil': 'Walang nakitang peste sa litratong ito.', 'krj': 'Wara it nakita nga peste sa litrato nga kadya.'},
  'Automatic analysis is unavailable. A technician will identify the pest.': {
    'fil': 'Hindi magamit ang awtomatikong pagsusuri. Ang technician ang tutukoy sa peste.',
    'krj': 'Indi magamit ang awtomatiko nga pag-usisa. Ang technician ang mangilala sa peste.',
  },
  'No supported pest was recognized with confidence. A technician will check the photo.': {
    'fil': 'Walang suportadong peste na tiyak na nakilala. Titingnan ng technician ang litrato.',
    'krj': 'Wara it suportado nga peste nga sigurado nga nakilala. Turukon it technician ang litrato.',
  },
  'Possible pests were found, but not clearly enough to name one. A technician will identify it.': {
    'fil': 'May posibleng peste, pero hindi malinaw para matukoy. Ang technician ang tutukoy nito.',
    'krj': 'May posible nga peste, pero indi malinaw para makilala. Ang technician ang mangilala.',
  },
  'Other pests may also be in the photo; the technician will check.': {
    'fil': 'Baka may iba pang peste sa litrato; titingnan ng technician.',
    'krj': 'Basi may iban pa nga peste sa litrato; turukon it technician.',
  },
  'The insects are too close together to count reliably.': {
    'fil': 'Masyadong magkakadikit ang mga insekto para mabilang nang tama.',
    'krj': 'Masyado magkadikit ang mga insekto para maisip it husto.',
  },
  'The insects are not clear enough to count reliably.': {
    'fil': 'Hindi sapat na malinaw ang mga insekto para mabilang nang tama.',
    'krj': 'Indi malinaw gid ang mga insekto para maisip it husto.',
  },
  'The photo looks blurry; the technician may ask for a new one.': {
    'fil': 'Mukhang malabo ang litrato; baka humingi ng bago ang technician.',
    'krj': 'Daw malabo ang litrato; basi mangayo it bag-o ang technician.',
  },
  'The photo looks too dark; the technician may ask for a new one.': {
    'fil': 'Mukhang masyadong madilim ang litrato; baka humingi ng bago ang technician.',
    'krj': 'Daw madulom gid ang litrato; basi mangayo it bag-o ang technician.',
  },
  'Chemical control is a last resort. Talk to your agricultural technician or municipal agriculture office before using any pesticide, and always follow the label.': {
    'fil': 'Huling paraan ang kemikal. Kausapin muna ang iyong technician o municipal agriculture office bago gumamit ng pestisidyo, at laging sundin ang label.',
    'krj': 'Katapusan nga paagi ang kemikal. Hambali anay ang imo nga technician ukon municipal agriculture office antes maggamit it pestisidyo, kag permi sundon ang label.',
  },
  'The photo looks washed out by light; the technician may ask for a new one.': {
    'fil': 'Mukhang sobrang liwanag ang litrato; baka humingi ng bago ang technician.',
    'krj': 'Daw sobra kasanag ang litrato; basi mangayo it bag-o ang technician.',
  },
};
