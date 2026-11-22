// Translations (observe). Key = the English text used in the code.
// Each entry: {'fil': 'Filipino', 'krj': 'Kinaray-a (Antique)'}. Keep {placeholders} unchanged.
const Map<String, Map<String, String>> kObserveStrings = {
  // ---------------------------------------------------------------- f30 new observation: header, leaving
  'New Observation': {'fil': 'Bagong obserbasyon', 'krj': 'Bag-o nga obserbasyon'},
  'Retake photo': {'fil': 'Kunan ulit ang litrato', 'krj': 'Kuhaan liwan ang litrato'},
  'Follow-up check': {'fil': 'Follow-up na pagsuri', 'krj': 'Follow-up nga pag-usisa'},
  'Disease report': {'fil': 'Ulat ng sakit', 'krj': 'Report it balatian'},
  'Pest report': {'fil': 'Ulat ng peste', 'krj': 'Report it peste'},
  'Step {n} of {total}': {'fil': 'Hakbang {n} sa {total}', 'krj': 'Step {n} sa {total}'},
  'Discard this observation?': {'fil': 'Burahin ang obserbasyong ito?', 'krj': 'Panason ang obserbasyon nga dya?'},
  'The photo you took will not be sent.': {
    'fil': 'Hindi maipapadala ang litratong kinuha mo.',
    'krj': 'Indi mapadara ang litrato nga ginkuha mo.',
  },
  'Keep going': {'fil': 'Ituloy', 'krj': 'Padayon'},
  'Discard': {'fil': 'Burahin', 'krj': 'Panasa'},

  // follow-up and retake banners
  'How is the field now? This photo will be linked to your treatment.': {
    'fil': 'Kumusta na ang palayan? Para sa lunas mo ang litratong ito.',
    'krj': 'Kamusta run ang uma? Ang litrato nga dya para sa imo bulong.',
  },
  'How is the field now? This photo will be linked to "{treatment}".': {
    'fil': 'Kumusta na ang palayan? Para sa "{treatment}" ang litratong ito.',
    'krj': 'Kamusta run ang uma? Ang litrato nga dya para sa "{treatment}".',
  },
  'New photo for your disease report': {
    'fil': 'Bagong litrato para sa ulat ng sakit mo',
    'krj': 'Bag-o nga litrato para sa imo report it balatian',
  },
  'New photo for your pest report': {
    'fil': 'Bagong litrato para sa ulat ng peste mo',
    'krj': 'Bag-o nga litrato para sa imo report it peste',
  },
  'The technician could not see it clearly.': {
    'fil': 'Hindi ito malinaw na makita ng technician.',
    'krj': 'Indi klaro nga makita dya it technician.',
  },
  'The technician said: "{reason}"': {'fil': 'Sabi ng technician: "{reason}"', 'krj': 'Siling it technician: "{reason}"'},

  // ---------------------------------------------------------------- step: report type
  'What are you reporting?': {'fil': 'Ano ang iuulat mo?', 'krj': 'Ano ang imo i-report?'},
  'Insects, eggs, or plants they have damaged. The app looks for insects in your photo.': {
    'fil': 'Mga insekto, itlog, o halamang sinira nila. Hahanapin ng app ang mga insekto sa litrato mo.',
    'krj': 'Mga insekto, itlog, ukon tanum nga gin-guba nanda. Ginapangita it app ang mga insekto sa imo litrato.',
  },
  'Spots, discolored or dying leaves, strange growth. A technician checks it.': {
    'fil': 'Mga batik, dahong nag-iba ang kulay o namamatay, kakaibang paglaki. Susuriin ito ng technician.',
    'krj': 'Mga mansa, dahon nga nag-iba ang kolor ukon nagakalaya, lain nga pagtubo. Usisaon dya it technician.',
  },

  // ---------------------------------------------------------------- step: photo
  'Take a clear photo': {'fil': 'Kumuha ng malinaw na litrato', 'krj': 'Magkuha it klaro nga litrato'},
  'Get close so the insects or damage fill the picture. Hold the phone steady.': {
    'fil': 'Lumapit para puno ng insekto o pinsala ang litrato. Huwag igalaw ang phone.',
    'krj': 'Magpalapit para puno it insekto ukon danyos ang litrato. Kapti it mayad ang phone.',
  },
  'Use this photo': {'fil': 'Gamitin ang litratong ito', 'krj': 'Gamiton ang litrato nga dya'},
  'Open the camera': {'fil': 'Buksan ang camera', 'krj': 'Buksi ang camera'},
  'Take it again': {'fil': 'Kunan ulit', 'krj': 'Kuhaan liwan'},
  'Choose a photo from the gallery instead': {
    'fil': 'Pumili na lang ng litrato sa gallery',
    'krj': 'Magpili lang it litrato sa gallery',
  },
  'Could not save the photo on this device.': {
    'fil': 'Hindi ma-save ang litrato sa phone na ito.',
    'krj': 'Indi ma-save ang litrato sa phone nga dya.',
  },
  'Could not open the gallery.': {'fil': 'Hindi mabuksan ang gallery.', 'krj': 'Indi mabuksan ang gallery.'},

  // ---------------------------------------------------------------- step: location
  'Is this your field?': {'fil': 'Ito ba ang palayan mo?', 'krj': 'Dya bala ang imo uma?'},
  'Yes, this is my field': {'fil': 'Oo, ito ang palayan ko', 'krj': 'Huo, dya ang akon uma'},
  'No, find my location again': {
    'fil': 'Hindi, hanapin ulit ang lokasyon ko',
    'krj': 'Indi, pangitaa liwan ang akon lokasyon',
  },
  'Continue without location': {'fil': 'Ituloy nang walang lokasyon', 'krj': 'Padayon nga wara it lokasyon'},
  'Finding your location…': {'fil': 'Hinahanap ang lokasyon mo…', 'krj': 'Ginapangita ang imo lokasyon…'},
  'No location yet': {'fil': 'Wala pang lokasyon', 'krj': 'Wara pa it lokasyon'},
  'Location is turned off on your phone. Turn it on and we will try again.': {
    'fil': 'Naka-off ang location sa phone mo. I-on ito at susubukan namin ulit.',
    'krj': 'Naka-off ang location sa imo phone. I-on dya kag tilawan namon liwan.',
  },
  'Location permission is blocked for this app. You can allow it in your phone settings.': {
    'fil': 'Naka-block ang location permission ng app na ito. Puwede mo itong payagan sa settings ng phone mo.',
    'krj': 'Naka-block ang location permission it app nga dya. Pwede mo dya tugutan sa settings it imo phone.',
  },
  'The app needs permission to use your location.': {
    'fil': 'Kailangan ng app ng pahintulot para magamit ang lokasyon mo.',
    'krj': 'Kinahanglan it app it permiso para magamit ang imo lokasyon.',
  },
  'We could not get your location. Move to an open area and try again.': {
    'fil': 'Hindi makuha ang lokasyon mo. Pumunta sa lugar na walang harang at subukan ulit.',
    'krj': 'Indi makuha ang imo lokasyon. Magkadto sa lugar nga wara it harang kag tilawan liwan.',
  },
  'Try again': {'fil': 'Subukan ulit', 'krj': 'Tilawan liwan'},
  'Open settings': {'fil': 'Buksan ang settings', 'krj': 'Buksi ang settings'},

  // where the GPS point is (offline barangay lookup)
  'In {barangay}, {municipality}': {'fil': 'Sa {barangay}, {municipality}', 'krj': 'Sa {barangay}, {municipality}'},
  'GPS accuracy about {n} m': {'fil': 'Accuracy ng GPS: mga {n} m', 'krj': 'Accuracy it GPS: mga {n} m'},
  'Near {barangay}, {municipality}': {
    'fil': 'Malapit sa {barangay}, {municipality}',
    'krj': 'Malapit sa {barangay}, {municipality}',
  },
  'Close to a barangay boundary.': {
    'fil': 'Malapit sa hangganan ng barangay.',
    'krj': 'Malapit sa boundary it barangay.',
  },
  'The GPS is not accurate yet (about {n} m). Move to an open area and tap Try again.': {
    'fil': 'Hindi pa tumpak ang GPS (mga {n} m). Pumunta sa lugar na walang harang at i-tap ang Subukan ulit.',
    'krj': 'Indi pa husto ang GPS (mga {n} m). Magkadto sa lugar nga wara it harang kag i-tap ang Tilawan liwan.',
  },
  'This location is outside Antique. The observation will still be sent and filed under your saved barangay ({place}).': {
    'fil': 'Nasa labas ng Antique ang lokasyong ito. Ipapadala pa rin ang obserbasyon at itatala sa '
        'naka-save mong barangay ({place}).',
    'krj': 'Yara sa guwa it Antique ang lokasyon nga dya. Ipadara man gihapon ang obserbasyon kag itala sa '
        'imo naka-save nga barangay ({place}).',
  },
  "your account's area": {'fil': 'lugar sa account mo', 'krj': 'lugar sa imo account'},
  'Using your last known location.': {
    'fil': 'Ginagamit ang huling alam na lokasyon mo.',
    'krj': 'Ginagamit ang imo naulihi nga lokasyon.',
  },

  // ---------------------------------------------------------------- step: land type
  'What kind of land is this field?': {
    'fil': 'Anong uri ng lupa ang palayang ito?',
    'krj': 'Ano nga klase it duta ang uma nga dya?',
  },
  'Checking the elevation of your field…': {
    'fil': 'Tinitingnan ang taas ng palayan mo…',
    'krj': 'Ginausisa ang kataason it imo uma…',
  },
  'No suggestion right now (no signal). Pick the land type yourself.': {
    'fil': 'Walang mungkahi ngayon (walang signal). Ikaw na ang pumili ng uri ng lupa.',
    'krj': 'Wara it suhestyon makaron (wara it signal). Ikaw run ang magpili it klase it duta.',
  },
  "Without a location the app can't suggest one. Pick the land type yourself.": {
    'fil': 'Kung walang lokasyon, hindi makakapagmungkahi ang app. Ikaw na ang pumili ng uri ng lupa.',
    'krj': 'Kon wara it lokasyon, indi makasuhestyon ang app. Ikaw run ang magpili it klase it duta.',
  },
  '{label} (suggested)': {'fil': '{label} (mungkahi)', 'krj': '{label} (suhestyon)'},
  'The suggestion comes from the elevation only. Change it if your field is different.': {
    'fil': 'Batay lang sa taas ng lugar ang mungkahi. Palitan ito kung iba ang palayan mo.',
    'krj': 'Basi lang sa kataason it lugar ang suhestyon. Ilisi dya kon lain ang imo uma.',
  },
  // the server's elevation reasons (rice-pest-api/app/land.py), rebuilt in the app
  'Elevation could not be looked up. Pick the land type yourself.': {
    'fil': 'Hindi matingnan ang taas ng lugar. Ikaw na ang pumili ng uri ng lupa.',
    'krj': 'Indi maturukan ang kataason it lugar. Ikaw run ang magpili it klase it duta.',
  },
  'About {n} m above sea level, which suggests upland. Change it if the field is a flooded paddy.': {
    'fil': 'Mga {n} m ang taas mula sa dagat, kaya mukhang upland ito. Palitan kung palayang may tubig ito.',
    'krj': 'Mga {n} m ang kataason halin sa dagat, gani daw upland dya. Ilisi kon ang uma may tubig.',
  },
  'About {n} m above sea level, which suggests lowland. '
      'Pick rainfed or irrigated depending on where the water comes from.': {
    'fil': 'Mga {n} m ang taas mula sa dagat, kaya mukhang lowland ito. '
        'Piliin ang rainfed o irrigated depende kung saan galing ang tubig.',
    'krj': 'Mga {n} m ang kataason halin sa dagat, gani daw lowland dya. '
        'Pilia ang rainfed ukon irrigated depende kon diin halin ang tubig.',
  },

  // ---------------------------------------------------------------- step: crop stage
  'What stage is the rice?': {'fil': 'Anong yugto na ang palay?', 'krj': 'Ano run ang edad it humay?'},
  // crop stage values (stored in English; shown translated)
  'Vegetative': {'fil': 'Paglaki', 'krj': 'Pagtubo'},
  'Reproductive': {'fil': 'Pagbubuntis', 'krj': 'Pagbusog'},
  'Ripening': {'fil': 'Paghinog', 'krj': 'Paghinog'},

  // ---------------------------------------------------------------- step: monitoring method
  'How did you check?': {'fil': 'Paano mo sinuri?', 'krj': 'Paano mo gin-usisa?'},
  'Direct field observation': {'fil': 'Direktang pagtingin sa palayan', 'krj': 'Direkta nga pagturok sa uma'},
  'I looked at the plants': {'fil': 'Tiningnan ko ang mga halaman', 'krj': 'Ginturok ko ang mga tanum'},
  'Trap-based': {'fil': 'Gamit ang trap', 'krj': 'Paagi sa trap'},
  'From a sticky trap, light trap or lure': {
    'fil': 'Mula sa sticky trap, light trap o lure',
    'krj': 'Halin sa sticky trap, light trap ukon lure',
  },
  'Optional: add these only if you know them. The app never decides them on its own.': {
    'fil': 'Opsyonal: ilagay lang kung alam mo. Hindi ito kusang pinipili ng app.',
    'krj': 'Opsyonal: ibutang lang kon kabalo ka. Indi dya kusa nga ginapili it app.',
  },
  'Trap or lure type': {'fil': 'Uri ng trap o lure', 'krj': 'Klase it trap ukon lure'},
  'Target pest': {'fil': 'Target na peste', 'krj': 'Target nga peste'},
  'Target sex (if known)': {'fil': 'Lalaki o babae (kung alam)', 'krj': 'Lalaki ukon babayi (kon kabalo)'},
  'Not specified': {'fil': 'Hindi nakalagay', 'krj': 'Wara nakabutang'},
  // dropdown option values (stored in English; shown translated). Pest names stay as they are.
  'Sticky trap (yellow)': {'fil': 'Sticky trap (dilaw)', 'krj': 'Sticky trap (dalag)'},
  'Sticky trap (blue)': {'fil': 'Sticky trap (asul)', 'krj': 'Sticky trap (asul)'},
  'Light trap': {'fil': 'Light trap', 'krj': 'Light trap'},
  'Pheromone lure': {'fil': 'Pheromone lure', 'krj': 'Pheromone lure'},
  'Other trap': {'fil': 'Ibang trap', 'krj': 'Lain nga trap'},
  'Not sure': {'fil': 'Hindi sigurado', 'krj': 'Indi sigurado'},
  'Male': {'fil': 'Lalaki', 'krj': 'Lalaki'},
  'Female': {'fil': 'Babae', 'krj': 'Babayi'},
  'Not known': {'fil': 'Hindi alam', 'krj': 'Indi kabalo'},
  'Continue': {'fil': 'Ituloy', 'krj': 'Padayon'},

  // ---------------------------------------------------------------- step: notes
  'Describe what you see': {'fil': 'Isulat ang nakikita mo', 'krj': 'Isulat ang imo nakita'},
  'Anything to add?': {'fil': 'May idadagdag ka pa?', 'krj': 'May idugang ka pa?'},
  'Required. For example: color of the spots, which part of the plant, how much of the field.': {
    'fil': 'Kailangan. Halimbawa: kulay ng mga batik, anong bahagi ng halaman, gaano karami sa palayan.',
    'krj': 'Kinahanglan. Halimbawa: kolor it mga mansa, ano nga parte it tanum, daw ano kadamo sa uma.',
  },
  'Optional. For example: how many plants are affected, what you noticed.': {
    'fil': 'Opsyonal. Halimbawa: ilang halaman ang apektado, ano ang napansin mo.',
    'krj': 'Opsyonal. Halimbawa: pila ka tanum ang apektado, ano ang imo nakita.',
  },
  'What you observed…': {'fil': 'Ang napansin mo…', 'krj': 'Ang imo nakita…'},
  'Notes (optional)': {'fil': 'Notes (opsyonal)', 'krj': 'Notes (opsyonal)'},
  'Skip': {'fil': 'Laktawan', 'krj': 'I-skip'},

  // ---------------------------------------------------------------- step: summary and send
  'Ready to send?': {'fil': 'Handa nang ipadala?', 'krj': 'Handa run ipadara?'},
  'Photo': {'fil': 'Litrato', 'krj': 'Litrato'},
  'Taken': {'fil': 'Nakuha na', 'krj': 'Nakuha run'},
  'Location': {'fil': 'Lokasyon', 'krj': 'Lokasyon'},
  'Field confirmed on the map': {'fil': 'Kumpirmado sa mapa ang palayan', 'krj': 'Kumpirmado sa mapa ang uma'},
  'Not included': {'fil': 'Hindi kasama', 'krj': 'Wara nalakip'},
  'Included': {'fil': 'Kasama', 'krj': 'Nalakip'},
  'Land type': {'fil': 'Uri ng lupa', 'krj': 'Klase it duta'},
  'Crop stage': {'fil': 'Yugto ng palay', 'krj': 'Edad it humay'},
  'Report': {'fil': 'Ulat', 'krj': 'Report'},
  'Checked by': {'fil': 'Paraan ng pagsuri', 'krj': 'Paagi it pag-usisa'},
  'Notes': {'fil': 'Notes', 'krj': 'Notes'},
  'Change': {'fil': 'Palitan', 'krj': 'Ilisi'},
  'Submit': {'fil': 'Ipadala', 'krj': 'Ipadara'},
  "No signal? That's fine. It is saved on your phone and sent when you are back in coverage.": {
    'fil': 'Walang signal? Ayos lang. Naka-save ito sa phone mo at ipapadala kapag may signal ka na ulit.',
    'krj': 'Wara it signal? OK lang. Naka-save dya sa imo phone kag mapadara kon may signal ka run liwan.',
  },
  'Send this observation?': {'fil': 'Ipadala ang obserbasyong ito?', 'krj': 'Ipadara ang obserbasyon nga dya?'},
  'Send this disease report?': {
    'fil': 'Ipadala ang ulat ng sakit na ito?',
    'krj': 'Ipadara ang report it balatian nga dya?',
  },
  'A technician will review your photo and description.': {
    'fil': 'Susuriin ng technician ang litrato at detalye mo.',
    'krj': 'Usisaon it technician ang imo litrato kag detalye.',
  },
  'The app will check the photo for pests, then a technician confirms the result.': {
    'fil': 'Susuriin ng app kung may peste sa litrato, tapos kukumpirmahin ng technician ang resulta.',
    'krj': 'Usisaon it app kon may peste sa litrato, dayon ang technician ang magkumpirma it resulta.',
  },
  'Yes, send it': {'fil': 'Oo, ipadala na', 'krj': 'Huo, ipadara run'},

  // ---------------------------------------------------------------- f46 result: no pests found
  'Your photo was checked for pests.': {
    'fil': 'Sinuri ang litrato mo kung may peste.',
    'krj': 'Gin-usisa ang imo litrato kon may peste.',
  },
  'No pests found': {'fil': 'Walang nakitang peste', 'krj': 'Wara it nakita nga peste'},
  "The photo was clear and no pests were seen. This observation is closed, so it doesn't need a technician. "
      'Keep checking your field and send a new photo anytime.': {
    'fil': 'Malinaw ang litrato at walang nakitang peste. Sarado na ang obserbasyong ito, kaya hindi na kailangan '
        'ng technician. Patuloy na tingnan ang palayan mo at magpadala ng bagong litrato kahit kailan.',
    'krj': 'Klaro ang litrato kag wara it nakita nga peste. Sarado run ang obserbasyon nga dya, gani indi run '
        'kinahanglan it technician. Padayon nga turuka ang imo uma kag magpadara it bag-o nga litrato bisan san-o.',
  },
};
