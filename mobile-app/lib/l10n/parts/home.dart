// Translations (home). Key = the English text used in the code.
// Each entry: {'fil': 'Filipino', 'krj': 'Kinaray-a (Antique)'}. Keep {placeholders} unchanged.
const Map<String, Map<String, String>> kHomeStrings = {
  // ---------------------------------------------------------------- f20 home: hero
  'Good morning,': {'fil': 'Magandang umaga,', 'krj': 'Mayad nga aga,'},
  'Good afternoon,': {'fil': 'Magandang hapon,', 'krj': 'Mayad nga hapon,'},
  'Good evening,': {'fil': 'Magandang gabi,', 'krj': 'Mayad nga gab-i,'},
  'Welcome': {'fil': 'Maligayang pagdating', 'krj': 'Mayad nga pag-abot'},
  'Technician': {'fil': 'Technician', 'krj': 'Technician'},
  'Farmer': {'fil': 'Magsasaka', 'krj': 'Mangunguma'},
  'Observations': {'fil': 'Obserbasyon', 'krj': 'Obserbasyon'},
  'Validated': {'fil': 'Na-validate', 'krj': 'Na-validate'},
  'In review': {'fil': 'Sinusuri', 'krj': 'Ginausisa'},

  // ---------------------------------------------------------------- f20 home: dashboard
  'Still no signal. They will be sent automatically.': {
    'fil': 'Wala pa ring signal. Kusa itong ipapadala.',
    'krj': 'Wara pa it signal. Automatic dya nga mapadara.',
  },
  '{n} observation saved on this phone, waiting for signal.': {
    'fil': '{n} obserbasyon ang naka-save sa cellphone na ito, naghihintay ng signal.',
    'krj': '{n} ka obserbasyon ang naka-save sa cellphone nga dya, nagahulat it signal.',
  },
  '{n} observations saved on this phone, waiting for signal.': {
    'fil': '{n} obserbasyon ang naka-save sa cellphone na ito, naghihintay ng signal.',
    'krj': '{n} ka obserbasyon ang naka-save sa cellphone nga dya, nagahulat it signal.',
  },
  'Send now': {'fil': 'Ipadala na', 'krj': 'Ipadara run'},
  'Local map': {'fil': 'Mapa ng lugar', 'krj': 'Mapa it lugar'},
  'Reports near you': {'fil': 'Mga report malapit sa iyo', 'krj': 'Mga report malapit sa imo'},
  'Treatments': {'fil': 'Mga lunas', 'krj': 'Mga bulong'},
  'Options & follow-ups': {'fil': 'Mga opsyon at follow-up', 'krj': 'Mga opsyon kag follow-up'},
  'What to look for': {'fil': 'Ano ang dapat hanapin', 'krj': 'Ano ang dapat pangitaon'},
  'Pests, damage and crop stages': {
    'fil': 'Peste, pinsala at yugto ng palay',
    'krj': 'Peste, danyos kag edad it humay',
  },

  // needs your attention
  'How is the field now?': {'fil': 'Kumusta na ang palayan?', 'krj': 'Kamusta run ang uma?'},
  'You applied "{treatment}" on {date}. Take a photo so your technician can see if it worked.': {
    'fil': 'In-apply mo ang "{treatment}" noong {date}. Kumuha ng litrato para makita ng technician mo kung umepekto ito.',
    'krj': 'Gin-apply mo ang "{treatment}" sa {date}. Magkuha it litrato para makita it technician mo kon nag-epekto dya.',
  },
  'Check the field': {'fil': 'Tingnan ang palayan', 'krj': 'Turuka ang uma'},
  'Retake needed': {'fil': 'Kailangang kunan ulit', 'krj': 'Kinahanglan kuhaan liwan'},
  'Your technician could not see the photo clearly.': {
    'fil': 'Hindi malinaw ang litrato para sa technician mo.',
    'krj': 'Indi klaro ang litrato para sa technician mo.',
  },
  'Your technician says: "{reason}"': {
    'fil': 'Sabi ng technician mo: "{reason}"',
    'krj': 'Siling it technician mo: "{reason}"',
  },
  'Open the report': {'fil': 'Buksan ang report', 'krj': 'Buksi ang report'},
  'Disease report · {when}': {'fil': 'Report ng sakit · {when}', 'krj': 'Report it balatian · {when}'},
  'Pest report · {when}': {'fil': 'Report ng peste · {when}', 'krj': 'Report it peste · {when}'},
  '{title}: {level} infestation': {
    'fil': '{title}: {level} na antas ng peste',
    'krj': '{title}: {level} nga lebel it peste',
  },
  'Validated by your technician. See the treatment options for your crop stage.': {
    'fil': 'Na-validate na ng technician mo. Tingnan ang mga pwedeng lunas para sa yugto ng palay mo.',
    'krj': 'Na-validate run it technician mo. Turuka ang mga pwede nga bulong para sa edad it imo humay.',
  },
  'See treatment options': {'fil': 'Tingnan ang mga lunas', 'krj': 'Turuka ang mga bulong'},
  'Needs your attention': {'fil': 'Kailangan mong tingnan', 'krj': 'Kinahanglan mo turukon'},
  'See all': {'fil': 'Tingnan lahat', 'krj': 'Turuka tanan'},

  // treatment success
  'Treatment success': {'fil': 'Epekto ng lunas', 'krj': 'Epekto it bulong'},
  'Follow-ups done': {'fil': 'Mga natapos na follow-up', 'krj': 'Mga natapos nga follow-up'},
  '{a} of {b} treated field improved after the follow-up check.': {
    'fil': '{a} sa {b} palayang nilunasan ang gumanda pagkatapos ng follow-up.',
    'krj': '{a} sa {b} ka uma nga ginbulong ang nag-ayad pagkatapos it follow-up.',
  },
  '{a} of {b} treated fields improved after the follow-up check.': {
    'fil': '{a} sa {b} palayang nilunasan ang gumanda pagkatapos ng follow-up.',
    'krj': '{a} sa {b} ka uma nga ginbulong ang nag-ayad pagkatapos it follow-up.',
  },
  '{a} of {b} treatment checked again. Follow-ups show if a treatment worked.': {
    'fil': '{a} sa {b} lunas ang nasuri ulit. Makikita sa follow-up kung umepekto ang lunas.',
    'krj': '{a} sa {b} ka bulong ang gin-usisa liwan. Makita sa follow-up kon nag-epekto ang bulong.',
  },
  '{a} of {b} treatments checked again. Follow-ups show if a treatment worked.': {
    'fil': '{a} sa {b} lunas ang nasuri ulit. Makikita sa follow-up kung umepekto ang lunas.',
    'krj': '{a} sa {b} ka bulong ang gin-usisa liwan. Makita sa follow-up kon nag-epekto ang bulong.',
  },
  'Recent observations': {'fil': 'Mga bagong obserbasyon', 'krj': 'Mga bag-o nga obserbasyon'},

  // scan card and scan tips
  'Scan your field for pests': {
    'fil': 'I-scan ang palayan mo para sa peste',
    'krj': 'I-scan ang imo uma para sa peste',
  },
  'Take a photo. The app names the pest and counts the insects when it can.': {
    'fil': 'Kumuha ng litrato. Sasabihin ng app kung anong peste ito at bibilangin ang mga insekto kung kaya.',
    'krj': 'Magkuha it litrato. Isugid it app kon ano nga peste kag isipon ang mga insekto kon kaya.',
  },
  'Start pest scan': {'fil': 'Mag-scan ng peste', 'krj': 'Mag-scan it peste'},
  'Report disease': {'fil': 'I-report ang sakit', 'krj': 'I-report ang balatian'},
  'Scan tips': {'fil': 'Mga tip sa pag-scan', 'krj': 'Mga tip sa pag-scan'},
  'The app recognizes Brown Planthopper, Green Leafhopper, Rice Bug and Rice Stem Borer. '
      'It counts the insects only when they can be told apart.': {
    'fil': 'Nakikilala ng app ang Brown Planthopper, Green Leafhopper, Rice Bug at Rice Stem Borer. '
        'Binibilang lang nito ang mga insekto kapag malinaw na makita ang bawat isa.',
    'krj': 'Kilala it app ang Brown Planthopper, Green Leafhopper, Rice Bug kag Rice Stem Borer. '
        'Ginaisip lang na ang mga insekto kon klaro ang kada isa.',
  },
  'Get close': {'fil': 'Lumapit', 'krj': 'Magpalapit'},
  'Fill the picture with the insects or the damage.': {
    'fil': 'Dapat puno ng insekto o pinsala ang litrato.',
    'krj': 'Dapat puno it insekto ukon danyos ang litrato.',
  },
  'Hold steady': {'fil': 'Huwag igalaw', 'krj': 'Kapti it mayad'},
  'Tap the screen to focus and keep the phone still.': {
    'fil': 'I-tap ang screen para mag-focus at huwag igalaw ang cellphone.',
    'krj': 'I-tap ang screen para mag-focus kag kapti it mayad ang cellphone.',
  },
  'Use daylight': {'fil': 'Gamitin ang liwanag ng araw', 'krj': 'Gamita ang sanag it adlaw'},
  'Avoid strong shadows and night photos.': {
    'fil': 'Iwasan ang makapal na anino at litrato sa gabi.',
    'krj': 'Likawan ang madulom nga landong kag litrato sa gab-i.',
  },
  'Sticky traps': {'fil': 'Mga sticky trap', 'krj': 'Mga sticky trap'},
  'Photograph the whole trap, flat and straight on.': {
    'fil': 'Kunan ang buong trap, nakapatag at diretso.',
    'krj': 'Kuhaan ang bilog nga trap, patag kag diretso.',
  },
  'One spot per photo': {'fil': 'Isang lugar bawat litrato', 'krj': 'Isa ka lugar kada litrato'},
  'Send one observation for each field or trap.': {
    'fil': 'Magpadala ng isang obserbasyon sa bawat palayan o trap.',
    'krj': 'Magpadara it isa ka obserbasyon kada uma ukon trap.',
  },

  // technician: validation queue
  'Validation queue': {'fil': 'Pila para sa validation', 'krj': 'Pila para sa validation'},
  'Observations in your area': {'fil': 'Mga obserbasyon sa lugar mo', 'krj': 'Mga obserbasyon sa imo lugar'},
  'Action needed': {'fil': 'May gagawin', 'krj': 'May ubrahon'},
  'All caught up': {'fil': 'Tapos na lahat', 'krj': 'Tapos run tanan'},
  'No signal. Pull down to try again.': {
    'fil': 'Walang signal. Hilahin pababa para subukan ulit.',
    'krj': 'Wara it signal. Iguyod paidalom para tilawan liwan.',
  },
  'Pest': {'fil': 'Peste', 'krj': 'Peste'},
  'Disease': {'fil': 'Sakit', 'krj': 'Balatian'},
  'None': {'fil': 'Wala', 'krj': 'Wara'},
  'Oldest waiting': {'fil': 'Pinakamatagal naghihintay', 'krj': 'Pinakadugay nagahulat'},
  'Review now': {'fil': 'Suriin na', 'krj': 'Usisaa run'},
  'Open the queue': {'fil': 'Buksan ang pila', 'krj': 'Buksi ang pila'},

  // scan history
  'Scan history': {'fil': 'Mga nakaraang scan', 'krj': 'Mga nagligad nga scan'},
  'Last 4 weeks': {'fil': 'Nakaraang 4 na linggo', 'krj': 'Nagligad nga 4 ka semana'},
  '3 weeks ago': {'fil': '3 linggo na', 'krj': '3 semana run'},
  '2 weeks ago': {'fil': '2 linggo na', 'krj': '2 semana run'},
  'Last week': {'fil': 'Nakaraang linggo', 'krj': 'Nagligad nga semana'},
  'This week': {'fil': 'Ngayong linggo', 'krj': 'Kadya nga semana'},
  'Low': {'fil': 'Mababa', 'krj': 'Manubo'},
  'Medium': {'fil': 'Katamtaman', 'krj': 'Tunga-tunga'},
  'High': {'fil': 'Mataas', 'krj': 'Mataas'},
  'Not validated yet': {'fil': 'Hindi pa na-validate', 'krj': 'Wara pa na-validate'},
  'Pending': {'fil': 'Naghihintay', 'krj': 'Nagahulat'},

  // ---------------------------------------------------------------- f21 my records
  'My Records': {'fil': 'Aking mga rekord', 'krj': 'Akon nga mga rekord'},
  '{n} observation you sent': {
    'fil': '{n} obserbasyon na ipinadala mo',
    'krj': '{n} ka obserbasyon nga ginpadara mo',
  },
  '{n} observations you sent': {
    'fil': '{n} obserbasyon na ipinadala mo',
    'krj': '{n} ka obserbasyon nga ginpadara mo',
  },
  'All': {'fil': 'Lahat', 'krj': 'Tanan'},
  'Not sent': {'fil': 'Hindi pa naipadala', 'krj': 'Wara pa napadara'},
  'Returned': {'fil': 'Ibinalik', 'krj': 'Ginbalik'},
  'Nothing here yet': {'fil': 'Wala pang laman dito', 'krj': 'Wara pa it unod diya'},
  'Observations you send will appear here with their status.': {
    'fil': 'Lalabas dito ang mga obserbasyong ipapadala mo, kasama ang status nito.',
    'krj': 'Makita diya ang mga obserbasyon nga ipadara mo, upod ang ila status.',
  },
  'New Observation': {'fil': 'Bagong obserbasyon', 'krj': 'Bag-o nga obserbasyon'},
  'No {filter} records': {'fil': 'Walang rekord na {filter}', 'krj': 'Wara it rekord nga {filter}'},
  'Try another filter to see your other observations.': {
    'fil': 'Subukan ang ibang filter para makita ang iba mong obserbasyon.',
    'krj': 'Tilawan ang iban nga filter para makita ang iban mo nga obserbasyon.',
  },
  'Show all': {'fil': 'Ipakita lahat', 'krj': 'Ipakita tanan'},

  // ---------------------------------------------------------------- f25 notifications
  'No signal. Showing follow-ups saved on your phone.': {
    'fil': 'Walang signal. Ipinapakita ang mga follow-up na naka-save sa cellphone mo.',
    'krj': 'Wara it signal. Ginapakita ang mga follow-up nga naka-save sa imo cellphone.',
  },
  'Notifications': {'fil': 'Mga abiso', 'krj': 'Mga pahibaro'},
  '{n} unread': {'fil': '{n} hindi pa nabasa', 'krj': '{n} wara pa nabasa'},
  'Mark all read': {'fil': 'Markahang nabasa lahat', 'krj': 'Markahan tanan nabasa'},
  'Retry': {'fil': 'Subukan ulit', 'krj': 'Tilawan liwan'},
  'You applied "{treatment}" on {date} for {title}.': {
    'fil': 'In-apply mo ang "{treatment}" noong {date} para sa {title}.',
    'krj': 'Gin-apply mo ang "{treatment}" sa {date} para sa {title}.',
  },
  "You're all caught up": {'fil': 'Wala nang bagong abiso', 'krj': 'Wara run it bag-o nga pahibaro'},
  'You will be told here when a technician reviews your observations.': {
    'fil': 'Dito ka aabisuhan kapag sinuri ng technician ang mga obserbasyon mo.',
    'krj': 'Diya mo makita kon usisaon run it technician ang imo mga obserbasyon.',
  },

  // ---------------------------------------------------------------- f26 treatments
  'Options, what you applied, and follow-ups': {
    'fil': 'Mga opsyon, mga in-apply mo, at follow-up',
    'krj': 'Mga opsyon, ang gin-apply mo, kag follow-up',
  },
  'No treatments yet': {'fil': 'Wala pang lunas', 'krj': 'Wara pa it bulong'},
  'When a technician validates your pest report, the treatment options for your crop stage '
      'appear here. Log what you apply and the app reminds you to check the field.': {
    'fil': 'Kapag na-validate ng technician ang report mo ng peste, lalabas dito ang mga lunas para sa yugto ng '
        'palay mo. Itala ang in-apply mo at ipapaalala ng app na tingnan ang palayan.',
    'krj': 'Kon ma-validate it technician ang imo report it peste, makita diya ang mga bulong para sa edad it imo '
        'humay. Ilista ang gin-apply mo kag ipadumdom it app nga turukon ang uma.',
  },
  'Follow-up reminders': {'fil': 'Mga paalala sa follow-up', 'krj': 'Mga padumdom sa follow-up'},
  'Ready for treatment': {'fil': 'Handa nang lunasan', 'krj': 'Handa run bulongon'},
  'Validated by your technician. Open one to see the approved options for its crop stage.': {
    'fil': 'Na-validate na ng technician mo. Buksan ang isa para makita ang mga aprubadong lunas para sa yugto ng palay nito.',
    'krj': 'Na-validate run it technician mo. Buksi ang isa para makita ang mga aprobado nga bulong para sa edad it humay.',
  },
  'What you applied': {'fil': 'Mga in-apply mo', 'krj': 'Ang gin-apply mo'},
  'Checks due': {'fil': 'Dapat tingnan', 'krj': 'Dapat turukon'},
  'To treat': {'fil': 'Lulunasan', 'krj': 'Bulongon'},
  'Applied': {'fil': 'Na-apply', 'krj': 'Na-apply'},
  'Waiting for signal': {'fil': 'Naghihintay ng signal', 'krj': 'Nagahulat it signal'},
  'Follow-up sent': {'fil': 'Naipadala ang follow-up', 'krj': 'Napadara ang follow-up'},
  'Follow-up due now': {'fil': 'Oras na ng follow-up', 'krj': 'Oras run it follow-up'},
  'Follow-up {date}': {'fil': 'Follow-up sa {date}', 'krj': 'Follow-up sa {date}'},

  // ---------------------------------------------------------------- f27 guide
  'No signal, and the guide has not been saved on this phone yet.': {
    'fil': 'Walang signal, at hindi pa naka-save ang gabay sa cellphone na ito.',
    'krj': 'Wara it signal, kag wara pa naka-save ang giya sa cellphone nga dya.',
  },
  'Pests and the damage they cause': {'fil': 'Mga peste at ang pinsala nila', 'krj': 'Mga peste kag ang ila danyos'},
  "Can't load the guide": {'fil': 'Hindi ma-load ang gabay', 'krj': 'Indi ma-load ang giya'},
  'Try again': {'fil': 'Subukan ulit', 'krj': 'Tilawan liwan'},
  'No signal. Showing the guide saved on this phone.': {
    'fil': 'Walang signal. Ipinapakita ang gabay na naka-save sa cellphone na ito.',
    'krj': 'Wara it signal. Ginapakita ang giya nga naka-save sa cellphone nga dya.',
  },
  'Damage to look for': {'fil': 'Pinsalang dapat hanapin', 'krj': 'Danyos nga dapat pangitaon'},
  'Example photo not added yet': {'fil': 'Wala pang halimbawang litrato', 'krj': 'Wara pa it sampol nga litrato'},
};
