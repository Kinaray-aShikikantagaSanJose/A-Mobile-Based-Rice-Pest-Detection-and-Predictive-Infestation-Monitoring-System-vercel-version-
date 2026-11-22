// Translations (records). Key = the English text used in the code.
// Each entry: {'fil': 'Filipino', 'krj': 'Kinaray-a (Antique)'}. Keep {placeholders} unchanged.
const Map<String, Map<String, String>> kRecordsStrings = {
  // ---------------------------------------------------------------- f24 record detail
  'Record': {'fil': 'Rekord', 'krj': 'Rekord'},
  "Can't open this record": {'fil': 'Hindi mabuksan ang rekord na ito', 'krj': 'Indi mabuksan ang rekord nga dya'},
  'Tap to zoom': {'fil': 'Pindutin para lumaki', 'krj': 'Pinduta para magdako'},
  'Still no connection. It will be sent automatically.': {
    'fil': 'Wala pa ring koneksyon. Kusa itong ipapadala.',
    'krj': 'Wara pa it koneksyon. Automatic dya nga mapadara.',
  },
  'It will be removed from this phone and not sent.': {
    'fil': 'Mabubura ito sa phone na ito at hindi ipapadala.',
    'krj': 'Mapanas dya sa phone nga dya kag indi mapadara.',
  },
  'Keep it': {'fil': 'Itabi', 'krj': 'Itago lang'},
  'Discard this observation': {'fil': 'Itapon ang obserbasyong ito', 'krj': 'Panasa ang obserbasyon nga dya'},

  // waiting / in review / returned
  'It could not be sent: {error}': {'fil': 'Hindi ito naipadala: {error}', 'krj': 'Wara dya napadara: {error}'},
  'This observation is saved on your phone and will be sent when you are back in signal.': {
    'fil': 'Naka-save ang obserbasyong ito sa phone mo at ipapadala kapag may signal ka na ulit.',
    'krj': 'Naka-save ang obserbasyon nga dya sa imo phone kag ipadara kon may signal ka run liwan.',
  },
  'The pest check happens after it is sent, so there is no result yet.': {
    'fil': 'Susuriin ang peste pagkatapos itong maipadala, kaya wala pang resulta.',
    'krj': 'Usisaon ang peste pagkatapos dya mapadara, gani wara pa it resulta.',
  },
  'Try sending now': {'fil': 'Subukang ipadala ngayon', 'krj': 'Tilawan ipadara makaron'},
  'Sent for review by an agricultural technician. You will get a notification with the diagnosis and what to do.': {
    'fil': 'Naipadala na para suriin ng agricultural technician. May darating na abiso sa iyo kasama ang diagnosis at ang dapat gawin.',
    'krj': 'Napadara run para usisaon it agricultural technician. May maabot nga pahibaro sa imo upod ang diagnosis kag ang dapat himuon.',
  },
  'Your technician asked an agriculturist to take a closer look. You will get a notification when there is an answer.': {
    'fil': 'Ipinasuri ng technician mo sa isang agriculturist. May darating na abiso sa iyo kapag may sagot na.',
    'krj': 'Ginpausisa it technician mo sa agriculturist. May maabot nga pahibaro sa imo kon may sabat run.',
  },
  'Your technician says:': {'fil': 'Sabi ng technician mo:', 'krj': 'Siling it technician mo:'},
  'Please take the photo again.': {'fil': 'Pakikunan ulit ang litrato.', 'krj': 'Palihog kuhaan liwan ang litrato.'},
  'You already sent a new photo. It goes through the check again.': {
    'fil': 'Nakapagpadala ka na ng bagong litrato. Susuriin ulit ito.',
    'krj': 'Nakapadara ka run it bag-o nga litrato. Usisaon dya liwan.',
  },
  'Open the new photo': {'fil': 'Buksan ang bagong litrato', 'krj': 'Buksi ang bag-o nga litrato'},
  'Retake the photo': {'fil': 'Kunan ulit ang litrato', 'krj': 'Kuhaan liwan ang litrato'},

  // no pests found
  'The photo was clear and no pests were seen, so this observation was closed without review. The photo was removed from the server to save space. Keep checking your field and send a new photo anytime.': {
    'fil': 'Malinaw ang litrato at walang nakitang peste, kaya isinara na ang obserbasyong ito nang hindi na sinuri. Binura ang litrato sa server para makatipid ng espasyo. Patuloy na bantayan ang palayan mo at magpadala ng bagong litrato kahit kailan.',
    'krj': 'Klaro ang litrato kag wara it nakita nga peste, gani ginsara run ang obserbasyon nga dya nga wara run gin-usisa. Ginpanas ang litrato sa server para makatipid it espasyo. Padayon nga bantayan ang imo uma kag magpadara it bag-o nga litrato bisan san-o.',
  },
  'The GPS point was outside Antique, so this was filed under your saved barangay.': {
    'fil': 'Nasa labas ng Antique ang GPS point, kaya inilagay ito sa naka-save mong barangay.',
    'krj': 'Yara sa guwa it Antique ang GPS point, gani ginbutang dya sa naka-save mo nga barangay.',
  },

  // validated
  'Confirmed by your technician': {'fil': 'Kinumpirma ng technician mo', 'krj': 'Ginkumpirma it technician mo'},
  'Diagnosis': {'fil': 'Diagnosis', 'krj': 'Diagnosis'},
  'What to do': {'fil': 'Ano ang dapat gawin', 'krj': 'Ano ang dapat himuon'},
  'Not countable': {'fil': 'Hindi mabilang', 'krj': 'Indi maisip'},
  'For the {stage} stage': {'fil': 'Para sa yugtong {stage}', 'krj': 'Para sa edad nga {stage}'},
  'Open this record with signal to see the options.': {
    'fil': 'Buksan ang rekord na ito kapag may signal para makita ang mga lunas.',
    'krj': 'Buksi ang rekord nga dya kon may signal para makita ang mga bulong.',
  },
  'No approved options for this case yet. Ask your agricultural technician what to do.': {
    'fil': 'Wala pang aprobadong lunas para sa kasong ito. Tanungin ang agricultural technician mo kung ano ang dapat gawin.',
    'krj': 'Wara pa it aprobado nga bulong para sa kaso nga dya. Pamangkuta ang imo agricultural technician kon ano ang dapat himuon.',
  },
  'Approved by your agriculture office for this pest, crop stage and level. Choose what fits your farm; your technician can help.': {
    'fil': 'Aprobado ng agriculture office para sa pesteng ito, yugto ng palay at antas. Piliin ang bagay sa bukid mo; matutulungan ka ng technician mo.',
    'krj': 'Aprobado it agriculture office para sa peste nga dya, edad it humay kag lebel. Pilia ang bagay sa imo uma; makabulig ang imo technician.',
  },
  'Source: {source}': {'fil': 'Pinagkunan: {source}', 'krj': 'Ginkuhaan: {source}'},
  'Not shown again because you already tried it and sent feedback: {titles}. Your technician can recommend it again.': {
    'fil': 'Hindi na ipinapakita dahil nasubukan mo na ito at nagpadala ka ng feedback: {titles}. Puwede itong irekomenda ulit ng technician mo.',
    'krj': 'Indi run ginapakita kay natilawan mo run dya kag nagpadara ka it feedback: {titles}. Pwede dya irekomenda liwan it imo technician.',
  },
  'Not shown again because you already tried them and sent feedback: {titles}. Your technician can recommend them again.': {
    'fil': 'Hindi na ipinapakita dahil nasubukan mo na ang mga ito at nagpadala ka ng feedback: {titles}. Puwede ulit itong irekomenda ng technician mo.',
    'krj': 'Indi run ginapakita kay natilawan mo run ang mga dya kag nagpadara ka it feedback: {titles}. Pwede man dya irekomenda liwan it imo technician.',
  },
  'I applied a treatment': {'fil': 'Nag-apply ako ng lunas', 'krj': 'Nag-apply ako it bulong'},
  'Applied treatments': {'fil': 'Mga in-apply na lunas', 'krj': 'Mga gin-apply nga bulong'},
  'It has been a while since you applied "{treatment}". Take a photo so your technician can see if it worked.': {
    'fil': 'Matagal-tagal na mula nang i-apply mo ang "{treatment}". Kumuha ng litrato para makita ng technician mo kung umepekto ito.',
    'krj': 'Medyo madugay run halin gin-apply mo ang "{treatment}". Magkuha it litrato para makita it technician mo kon nag-epekto dya.',
  },
  'Follow-up on {date}': {'fil': 'Follow-up sa {date}', 'krj': 'Follow-up sa {date}'},
  'Applied {date}': {'fil': 'In-apply noong {date}', 'krj': 'Gin-apply sa {date}'},
  'Follow-up date set by your technician': {
    'fil': 'Ang technician mo ang nagtakda ng petsa ng follow-up',
    'krj': 'Ang technician mo ang nagbutang it petsa it follow-up',
  },

  // log a treatment
  'What did you use?': {'fil': 'Ano ang ginamit mo?', 'krj': 'Ano ang gingamit mo?'},
  'Something else': {'fil': 'Iba pa', 'krj': 'Iba pa'},
  'Describe what you did': {'fil': 'Ilarawan ang ginawa mo', 'krj': 'Isaysay ang ginhimo mo'},
  'e.g. Removed weeds around the field': {
    'fil': 'hal. Nagbunot ng damo sa paligid ng palayan',
    'krj': 'Halimbawa: Ginbunot ang hilamon sa palibot it uma',
  },
  'Date applied': {'fil': 'Petsa ng pag-apply', 'krj': 'Petsa it pag-apply'},
  'Pick what you used, or describe it.': {
    'fil': 'Piliin ang ginamit mo, o ilarawan ito.',
    'krj': 'Pilia ang gingamit mo, ukon isaysay dya.',
  },
  'Log this treatment?': {'fil': 'Itala ang lunas na ito?', 'krj': 'Ilista ang bulong nga dya?'},
  'In about a week the app will remind you to check the field, so your technician can see if it worked.': {
    'fil': 'Pagkalipas ng mga isang linggo, ipapaalala ng app na tingnan mo ang palayan, para makita ng technician mo kung umepekto ito.',
    'krj': 'Pagkatapos it mga isa ka semana, ipahanumdom it app nga turukon mo ang uma, para makita it technician mo kon nag-epekto dya.',
  },
  'Yes, log it': {'fil': 'Oo, itala', 'krj': 'Huo, ilista'},
  'Treatment': {'fil': 'Lunas', 'krj': 'Bulong'},
  'For': {'fil': 'Para sa', 'krj': 'Para sa'},
  'Treatment logged': {'fil': 'Naitala ang lunas', 'krj': 'Nalista run ang bulong'},
  'We will remind you to check the field in about a week.': {
    'fil': 'Ipapaalala namin na tingnan mo ang palayan pagkalipas ng mga isang linggo.',
    'krj': 'Ipahanumdom namon nga turukon mo ang uma pagkatapos it mga isa ka semana.',
  },
  'No signal right now. It will be sent by itself when you are back in coverage.': {
    'fil': 'Walang signal ngayon. Kusa itong maipapadala kapag may signal ka na ulit.',
    'krj': 'Wara it signal makaron. Kusa dya nga mapadara kon may signal ka run liwan.',
  },
  'Not saved': {'fil': 'Hindi na-save', 'krj': 'Wara na-save'},
  'Saving your treatment…': {'fil': 'Sine-save ang lunas mo…', 'krj': 'Ginasave ang imo bulong…'},
  'It is kept on your phone first, then sent.': {
    'fil': 'Itatabi muna ito sa phone mo, saka ipapadala.',
    'krj': 'Itago anay dya sa imo phone, dayon ipadara.',
  },
  'View the record': {'fil': 'Tingnan ang rekord', 'krj': 'Turuka ang rekord'},

  // details
  'Details': {'fil': 'Detalye', 'krj': 'Detalye'},
  'New photo for report #{id}': {'fil': 'Bagong litrato para sa report #{id}', 'krj': 'Bag-o nga litrato para sa report #{id}'},
  'Trap or lure': {'fil': 'Bitag o pain', 'krj': 'Bitag ukon paon'},
  'Target sex': {'fil': 'Target na kasarian', 'krj': 'Target nga kasarian'},
  'Symptoms': {'fil': 'Sintomas', 'krj': 'Sintomas'},
  'Your notes': {'fil': 'Mga tala mo', 'krj': 'Imo mga nota'},
  'Checks on a treatment you applied': {
    'fil': 'Pagsuri sa lunas na in-apply mo',
    'krj': 'Pag-usisa sa bulong nga gin-apply mo',
  },
  'Area': {'fil': 'Lugar', 'krj': 'Lugar'},

  // ---------------------------------------------------------------- delete (technicians)
  'Delete record': {'fil': 'Burahin ang rekord', 'krj': 'Panasa ang rekord'},
  'Delete this observation?': {'fil': 'Burahin ang obserbasyong ito?', 'krj': 'Panason ang obserbasyon nga dya?'},
  "This removes the record, its photo, treatments and review history for everyone. The farmer is told in the app. This can't be undone.": {
    'fil': 'Mabubura para sa lahat ang rekord, ang litrato nito, mga lunas at kasaysayan ng pagsusuri. Sasabihan ang magsasaka sa app. Hindi na ito maibabalik.',
    'krj': 'Mapanas para sa tanan ang rekord, ang litrato, mga bulong kag history it pag-usisa. Pahibaruon ang mangunguma sa app. Indi run mabalik kadya.',
  },
  'Reason (optional, shown to the farmer)': {
    'fil': 'Dahilan (opsyonal, makikita ng magsasaka)',
    'krj': 'Rason (opsyonal, makita it mangunguma)',
  },
  'Delete': {'fil': 'Burahin', 'krj': 'Panasa'},
  'Cancel': {'fil': 'Kanselahin', 'krj': 'Indi lang'},
  'Observation deleted.': {'fil': 'Nabura na ang obserbasyon.', 'krj': 'Napanas run ang obserbasyon.'},
  'No signal. Deleting needs a connection; try again with signal.': {
    'fil': 'Walang signal. Kailangan ng koneksyon para makabura; subukan ulit kapag may signal.',
    'krj': 'Wara it signal. Kinahanglan it koneksyon para makapanas; tilawan liwan kon may signal.',
  },

  // ---------------------------------------------------------------- return reasons (shown to farmers)
  // Sent by technicians from the dashboard.
  'The photo is too blurry. Please take a new, closer photo.': {
    'fil': 'Malabo ang litrato. Kumuha ng bago at mas malapit na litrato.',
    'krj': 'Indi klaro ang litrato. Magkuha it bag-o kag mas malapit nga litrato.',
  },
  "The pest isn't visible in the photo. Please photograph the insects up close.": {
    'fil': 'Hindi makita ang peste sa litrato. Kunan nang malapitan ang mga insekto.',
    'krj': 'Indi makita ang peste sa litrato. Kuhaan it litrato ang mga insekto nga malapit gid.',
  },
  'The photo is too dark. Please retake it in daylight.': {
    'fil': 'Masyadong madilim ang litrato. Kunan ulit habang may araw pa.',
    'krj': 'Madulom gid ang litrato. Kuhaan liwan samtang adlaw pa.',
  },
  "The photo doesn't show a rice crop.": {'fil': 'Walang palay sa litrato.', 'krj': 'Wara it humay sa litrato.'},
  // Quick reasons on the review screen.
  'Photo too blurry': {'fil': 'Malabo ang litrato', 'krj': 'Indi klaro ang litrato'},
  'Too far away, move closer': {'fil': 'Masyadong malayo, lumapit pa', 'krj': 'Malayo gid, magpalapit pa'},
  'Too dark': {'fil': 'Masyadong madilim', 'krj': 'Madulom gid'},
  'Insects not visible': {'fil': 'Hindi makita ang mga insekto', 'krj': 'Indi makita ang mga insekto'},
  'Wrong photo': {'fil': 'Maling litrato', 'krj': 'Sala nga litrato'},
  // Quick escalation reasons.
  'Unclear what pest this is': {'fil': 'Hindi malinaw kung anong peste ito', 'krj': 'Indi klaro kon ano nga peste dya'},
  'Unusual damage': {'fil': 'Kakaibang pinsala', 'krj': 'Indi normal nga danyos'},
  'Possible outbreak': {'fil': 'Posibleng outbreak', 'krj': 'Posible nga outbreak'},
  'Not one of the four pests': {'fil': 'Hindi isa sa apat na peste', 'krj': 'Bukon isa sa apat ka peste'},

  // ---------------------------------------------------------------- f61 review
  'Review': {'fil': 'Pagsusuri', 'krj': 'Pag-usisa'},
  'Waiting {time} · #{id}': {'fil': 'Naghihintay nang {time} · #{id}', 'krj': 'Nagahulat it {time} · #{id}'},
  "Can't open this report": {'fil': 'Hindi mabuksan ang report na ito', 'krj': 'Indi mabuksan ang report nga dya'},
  'Already handled.': {'fil': 'Naasikaso na.', 'krj': 'Naasikaso run.'},
  'Check the symptoms': {'fil': 'Tingnan ang mga sintomas', 'krj': 'Turuka ang mga sintomas'},
  'Check the model result': {'fil': 'Tingnan ang resulta ng AI', 'krj': 'Turuka ang resulta it AI'},
  'Your decision': {'fil': 'Ang desisyon mo', 'krj': 'Ang imo desisyon'},
  'New photo for report #{id}, which was returned because the photo was unclear.': {
    'fil': 'Bagong litrato para sa report #{id}, na ibinalik dahil malabo ang litrato.',
    'krj': 'Bag-o nga litrato para sa report #{id}, nga ginbalik kay indi klaro ang litrato.',
  },
  'Follow-up check: this photo shows the field after a treatment.': {
    'fil': 'Follow-up: makikita sa litratong ito ang palayan pagkatapos ng lunas.',
    'krj': 'Follow-up: makita sa litrato nga dya ang uma pagkatapos it bulong.',
  },
  'Submitted by': {'fil': 'Ipinadala ni', 'krj': 'Ginpadara ni'},
  'Phone': {'fil': 'Cellphone', 'krj': 'Cellphone'},
  'Method': {'fil': 'Paraan', 'krj': 'Paagi'},
  'Farmer notes': {'fil': 'Tala ng magsasaka', 'krj': 'Nota it mangunguma'},

  // step 1: model result
  'The model result names no pest.': {
    'fil': 'Walang pesteng pinangalanan ang resulta ng AI.',
    'krj': 'Wara it peste nga ginngalanan ang resulta it AI.',
  },
  'Model result: {pest} · {sure} · {count}': {
    'fil': 'Resulta ng AI: {pest} · {sure} · {count}',
    'krj': 'Resulta it AI: {pest} · {sure} · {count}',
  },
  'Count': {'fil': 'Bilang', 'krj': 'Isip'},
  'Not named yet': {'fil': 'Wala pang pangalan', 'krj': 'Wara pa it ngaran'},
  'Not entered yet': {'fil': 'Wala pang nailagay', 'krj': 'Wara pa nabutang'},
  'Name it': {'fil': 'Pangalanan', 'krj': 'Ngalani'},
  'Correct': {'fil': 'Itama', 'krj': 'I-correct'},
  'Enter': {'fil': 'Ilagay', 'krj': 'Ibutang'},
  'Confirming the model result': {'fil': 'Kinukumpirma ang resulta ng AI', 'krj': 'Ginakumpirma ang resulta it AI'},
  'Corrected by you': {'fil': 'Itinama mo', 'krj': 'Gin-correct mo'},
  'Use the model result': {'fil': 'Gamitin ang resulta ng AI', 'krj': 'Gamiton ang resulta it AI'},
  'There is no model result for disease reports. Look at the photo and what the farmer describes.': {
    'fil': 'Walang resulta ng AI para sa report ng sakit. Tingnan ang litrato at ang inilarawan ng magsasaka.',
    'krj': 'Wara it resulta it AI para sa report it balatian. Turuka ang litrato kag ang ginsaysay it mangunguma.',
  },
  'Which pest is it?': {'fil': 'Anong peste ito?', 'krj': 'Ano nga peste dya?'},
  'How many insects?': {'fil': 'Ilan ang insekto?', 'krj': 'Pila ka insekto?'},
  'Count only when the insects can be told apart. Otherwise mark it not countable.': {
    'fil': 'Bilangin lang kapag makikilala ang bawat insekto. Kung hindi, markahan itong hindi mabilang.',
    'krj': 'Isipa lang kon makilala ang kada insekto. Kon indi, markahi dya nga indi maisip.',
  },
  'Use this count': {'fil': 'Gamitin ang bilang na ito', 'krj': 'Gamiton ang isip nga dya'},

  // step 2: decision
  'Return': {'fil': 'Ibalik', 'krj': 'Ibalik'},
  'The photo is unclear. The farmer retakes it.': {
    'fil': 'Malabo ang litrato. Kukunan ulit ito ng magsasaka.',
    'krj': 'Indi klaro ang litrato. Kuhaan liwan dya it mangunguma.',
  },
  'Validate': {'fil': 'I-validate', 'krj': 'I-validate'},
  'Confirm or override the infestation level.': {
    'fil': 'Kumpirmahin o palitan ang antas ng peste.',
    'krj': 'Kumpirmaha ukon ilisan ang lebel it peste.',
  },
  'Escalate': {'fil': 'Ipasa', 'krj': 'Ipasa'},
  'Complex case. Refer it to an agriculturist.': {
    'fil': 'Mahirap na kaso. Ipasa sa agriculturist.',
    'krj': 'Mabudlay nga kaso. Ipasa sa agriculturist.',
  },
  'Quick reasons': {'fil': 'Mabilisang dahilan', 'krj': 'Dali nga rason'},
  'What should the farmer fix? They will see this.': {
    'fil': 'Ano ang dapat ayusin ng magsasaka? Makikita nila ito.',
    'krj': 'Ano ang dapat ayuson it mangunguma? Makita nanda dya.',
  },
  'Return to the farmer': {'fil': 'Ibalik sa magsasaka', 'krj': 'Ibalik sa mangunguma'},
  'Why does it need an agriculturist?': {
    'fil': 'Bakit kailangan ng agriculturist?',
    'krj': 'Ham-at kinahanglan it agriculturist?',
  },
  'Refer to an agriculturist': {'fil': 'Ipasa sa agriculturist', 'krj': 'Ipasa sa agriculturist'},
  'Damage you can see': {'fil': 'Pinsalang nakikita mo', 'krj': 'Danyos nga makita mo'},
  'None listed for this pest.': {'fil': 'Walang nakalista para sa pesteng ito.', 'krj': 'Wara it nakalista para sa peste nga dya.'},
  'How bad is it in the field?': {'fil': 'Gaano kalala sa palayan?', 'krj': 'Ano kagrabe dya sa uma?'},
  'Infestation level': {'fil': 'Antas ng peste', 'krj': 'Lebel it peste'},
  'Overridden': {'fil': 'Binago', 'krj': 'Ginbaylo'},
  'Suggested level': {'fil': 'Mungkahing antas', 'krj': 'Ginasugyot nga lebel'},
  'Suggested': {'fil': 'Mungkahi', 'krj': 'Ginasugyot'},
  'Pick the level you see in the field.': {
    'fil': 'Piliin ang antas na nakikita mo sa palayan.',
    'krj': 'Pilia ang lebel nga makita mo sa uma.',
  },
  'Keep the suggested level to confirm it, or pick another to override it.': {
    'fil': 'Iwan ang mungkahing antas para kumpirmahin ito, o pumili ng iba para palitan.',
    'krj': 'Bilinan ang ginasugyot nga lebel para kumpirmahon, ukon magpili it iba para ilisan.',
  },
  'Diagnosis (optional)': {'fil': 'Diagnosis (opsyonal)', 'krj': 'Diagnosis (opsyonal)'},
  'Guidance for the farmer (optional)': {
    'fil': 'Payo para sa magsasaka (opsyonal)',
    'krj': 'Laygay para sa mangunguma (opsyonal)',
  },
  'Name the pest in step 1 first.': {
    'fil': 'Pangalanan muna ang peste sa hakbang 1.',
    'krj': 'Ngalani anay ang peste sa step 1.',
  },
  'Enter the count in step 1, or mark it not countable.': {
    'fil': 'Ilagay ang bilang sa hakbang 1, o markahan itong hindi mabilang.',
    'krj': 'Ibutang ang isip sa step 1, ukon markahi dya nga indi maisip.',
  },
  'Pick the infestation level.': {'fil': 'Piliin ang antas ng peste.', 'krj': 'Pilia ang lebel it peste.'},

  // damage indicators (from the server; sent back in English)
  'Hopperburn (yellowing and drying patches)': {
    'fil': 'Hopperburn (naninilaw at natutuyong bahagi)',
    'krj': 'Hopperburn (nagadalag kag nagauga nga parte)',
  },
  'Honeydew or sooty mold at the plant base': {
    'fil': 'Honeydew o itim na amag sa puno ng halaman',
    'krj': 'Honeydew ukon itom nga agup-op sa puno it tanom',
  },
  'Plants wilting or lodging': {'fil': 'Nalalanta o natutumba ang halaman', 'krj': 'Nagalaya ukon nagatumba ang tanom'},
  'Yellow-orange leaf discoloration (possible tungro)': {
    'fil': 'Dilaw-kahel na kulay ng dahon (posibleng tungro)',
    'krj': 'Dalag-orange nga kolor it dahon (posible nga tungro)',
  },
  'Stunted plants': {'fil': 'Bansot na halaman', 'krj': 'Bansot nga tanom'},
  'Reduced tillering': {'fil': 'Kaunti ang tiller', 'krj': 'Diutay ang tiller'},
  'Empty or unfilled grains': {'fil': 'Walang laman o hindi napunong butil', 'krj': 'Wara sulod ukon indi napuno nga lugas'},
  'Brown spots on grains': {'fil': 'Brown na batik sa butil', 'krj': 'Brown nga mantsa sa lugas'},
  'Offensive rice-bug odor in the field': {
    'fil': 'Mabahong amoy ng rice bug sa palayan',
    'krj': 'Mabaho nga baho it rice bug sa uma',
  },
  'Deadhearts (dead central tiller)': {
    'fil': 'Deadheart (patay na gitnang tiller)',
    'krj': 'Deadheart (patay nga tunga nga tiller)',
  },
  'Whiteheads (empty white panicles)': {
    'fil': 'Whitehead (puting uhay na walang laman)',
    'krj': 'Whitehead (puti nga uhay nga wara sulod)',
  },
  'Bore holes or frass on stems': {'fil': 'Butas o dumi ng uod sa tangkay', 'krj': 'Buho ukon ipot it ulod sa tangkay'},
  'Visible feeding damage on leaves': {'fil': 'May kinain na bahagi sa dahon', 'krj': 'May ginkaon nga parte sa dahon'},
  'Plants wilting or dying': {'fil': 'Nalalanta o namamatay ang halaman', 'krj': 'Nagalaya ukon nagapatay ang tanom'},
  'Damage spread across much of the field': {
    'fil': 'Kalat ang pinsala sa malaking bahagi ng palayan',
    'krj': 'Lapnag ang danyos sa dako nga parte it uma',
  },

  // why the level is suggested (from the server)
  'No reliable count, so the suggestion starts at LOW and rests on the damage you saw': {
    'fil': 'Walang maaasahang bilang, kaya nagsisimula sa Mababa ang mungkahi at nakabatay sa pinsalang nakita mo',
    'krj': 'Wara it masaligan nga isip, gani nagasugod sa Manubo ang sugyot kag nakabase sa danyos nga nakita mo',
  },
  'No thresholds set for this pest, so the suggestion starts at LOW': {
    'fil': 'Walang threshold para sa pesteng ito, kaya nagsisimula sa Mababa ang mungkahi',
    'krj': 'Wara it threshold para sa peste nga dya, gani nagasugod sa Manubo ang sugyot',
  },
  '+1 level: {damage}': {'fil': '+1 antas: {damage}', 'krj': '+1 lebel: {damage}'},
  'Count {n}: {level} for {stage} (MEDIUM from {medium}, HIGH from {high})': {
    'fil': 'Bilang {n}: {level} para sa {stage} (Katamtaman mula {medium}, Mataas mula {high})',
    'krj': 'Isip {n}: {level} para sa {stage} (Tunga-tunga halin {medium}, Mataas halin {high})',
  },
  'any stage': {'fil': 'anumang yugto', 'krj': 'bisan ano nga edad'},

  // confirm and send
  'Return to the farmer?': {'fil': 'Ibalik sa magsasaka?', 'krj': 'Ibalik sa mangunguma?'},
  'They will be asked to take the photo again.': {
    'fil': 'Hihilingin sa kanila na kunan ulit ang litrato.',
    'krj': 'Pangabayon sanda nga kuhaan liwan ang litrato.',
  },
  'Returned to the farmer': {'fil': 'Naibalik sa magsasaka', 'krj': 'Nabalik run sa mangunguma'},
  'They will see your note and send a new photo.': {
    'fil': 'Makikita nila ang tala mo at magpapadala sila ng bagong litrato.',
    'krj': 'Makita nanda ang imo nota kag magpadara sanda it bag-o nga litrato.',
  },
  'Reason': {'fil': 'Dahilan', 'krj': 'Rason'},
  'Refer to an agriculturist?': {'fil': 'Ipasa sa agriculturist?', 'krj': 'Ipasa sa agriculturist?'},
  'The case leaves your queue and goes to an agriculturist.': {
    'fil': 'Aalis ang kaso sa pila mo at mapupunta sa agriculturist.',
    'krj': 'Mahalin ang kaso sa imo pila kag makadto sa agriculturist.',
  },
  'Sent to an agriculturist': {'fil': 'Naipasa sa agriculturist', 'krj': 'Napasa run sa agriculturist'},
  'An agriculturist will diagnose it and guide the farmer.': {
    'fil': 'Susuriin ito ng agriculturist at gagabayan ang magsasaka.',
    'krj': 'Usisaon dya it agriculturist kag tuytuyan ang mangunguma.',
  },
  'Validate this report?': {'fil': 'I-validate ang report na ito?', 'krj': 'I-validate ang report nga dya?'},
  'The farmer gets the result and the treatment options for their crop stage.': {
    'fil': 'Matatanggap ng magsasaka ang resulta at ang mga lunas para sa yugto ng palay nila.',
    'krj': 'Mabaton it mangunguma ang resulta kag ang mga bulong para sa edad it anda humay.',
  },
  'The farmer has been notified and can now see the treatment options.': {
    'fil': 'Naabisuhan na ang magsasaka at makikita na niya ang mga lunas.',
    'krj': 'Napahibaro run ang mangunguma kag makita run nana ang mga bulong.',
  },
  'Level': {'fil': 'Antas', 'krj': 'Lebel'},
  '{level} (overridden)': {'fil': '{level} (binago)', 'krj': '{level} (ginbaylo)'},
  'Yes, send': {'fil': 'Oo, ipadala', 'krj': 'Huo, ipadara'},
  'Not sent: no signal': {'fil': 'Hindi naipadala: walang signal', 'krj': 'Wara napadara: wara it signal'},
  'Sending your decision…': {'fil': 'Ipinapadala ang desisyon mo…', 'krj': 'Ginapadara ang imo desisyon…'},
  'This takes a moment.': {'fil': 'Sandali lang ito.', 'krj': 'Madali lang dya.'},
  'Next in queue': {'fil': 'Susunod sa pila', 'krj': 'Sunod sa pila'},
};
