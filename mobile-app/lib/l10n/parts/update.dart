// Translations (offline/cache notes, sign-out confirmation, review notes and
// recommendations, before/after, guide sections, land type changes, queues).
// Key = the English text used in the code.
// Each entry: {'fil': 'Filipino', 'krj': 'Kinaray-a (Antique)'}. Keep {placeholders} unchanged.
// Machine-assisted translations; not yet reviewed by a language expert.
const Map<String, Map<String, String>> kUpdateStrings = {
  // ---- lib/widgets/app_widgets.dart (saved data, errors, sign-out)
  'Showing saved data from {time}': {
    'fil': 'Ipinapakita ang naka-save na datos mula {time}',
    'krj': 'Ginapakita ang naka-save nga datos halin {time}',
  },
  "Couldn't load this": {'fil': 'Hindi ito ma-load', 'krj': 'Indi ini ma-load'},
  'Something went wrong. Please try again.': {
    'fil': 'May nagkaproblema. Pakisubukan ulit.',
    'krj': 'May nagproblema. Palihog tilawan liwan.',
  },
  'Sign out?': {'fil': 'Mag-sign out?', 'krj': 'Mag-sign out?'},
  'Everything is sent. You can sign in again any time with the same email and password.': {
    'fil': 'Naipadala na ang lahat. Puwede kang mag-sign in ulit kahit kailan gamit ang parehong email at password.',
    'krj': 'Napadara run tanan. Pwede ka mag-sign in liwan bisan san-o gamit ang pareho nga email kag password.',
  },
  'These are not sent yet. They stay on this phone and are sent after you sign in again with the same account. If a different account signs in on this phone, they are removed.': {
    'fil': 'Hindi pa naipapadala ang mga ito. Mananatili sila sa phone na ito at ipapadala pagkatapos mong mag-sign in ulit sa parehong account. Kung ibang account ang mag-sign in sa phone na ito, mabubura sila.',
    'krj': 'Wara pa napadara ang mga dya. Magapabilin sanda sa phone nga dya kag ipadara pagkatapos mo mag-sign in liwan sa pareho nga account. Kon iba nga account ang mag-sign in sa phone nga dya, mapanas sanda.',
  },
  'Observations not sent': {'fil': 'Mga obserbasyong hindi pa naipadala', 'krj': 'Mga obserbasyon nga wara pa napadara'},
  'Treatments not sent': {'fil': 'Mga lunas na hindi pa naipadala', 'krj': 'Mga bulong nga wara pa napadara'},

  // ---- lib/utils/formatters.dart (status labels)
  'Waiting for review': {'fil': 'Naghihintay ng pagsusuri', 'krj': 'Nagahulat it pag-usisa'},
  'Not Validated': {'fil': 'Hindi pa Na-validate', 'krj': 'Wara pa Na-validate'},
  'To Be Validated (agriculturist)': {
    'fil': 'Ive-validate pa (agriculturist)',
    'krj': 'I-validate pa (agriculturist)',
  },
  'Not Validated queue': {'fil': 'Pila ng Hindi pa Na-validate', 'krj': 'Pila it Wara pa Na-validate'},

  // ---- lib/screens/f15_profile.dart
  'Remove your profile picture?': {'fil': 'Alisin ang iyong profile picture?', 'krj': 'Kuhaon ang imo profile picture?'},
  'Your initials are shown instead. You can add a new picture any time.': {
    'fil': 'Ang iyong initials ang ipapakita. Puwede kang magdagdag ng bagong larawan kahit kailan.',
    'krj': 'Ang imo initials ang ipakita. Pwede ka magdugang it bag-o nga litrato bisan san-o.',
  },

  // ---- lib/screens/f31_camera_ui.dart
  'Discard this photo?': {'fil': 'Itapon ang litratong ito?', 'krj': 'Ipanas ang litrato nga dya?'},
  'The photo will be deleted from this phone.': {
    'fil': 'Mabubura ang litrato sa phone na ito.',
    'krj': 'Mapanas ang litrato sa phone nga dya.',
  },

  // ---- lib/screens/f24_record_detail.dart
  'Showing the copy saved on this phone.': {
    'fil': 'Ipinapakita ang kopyang naka-save sa phone na ito.',
    'krj': 'Ginapakita ang kopya nga naka-save sa phone nga dya.',
  },
  'Showing the copy saved on this phone while it refreshes.': {
    'fil': 'Ipinapakita ang kopyang naka-save sa phone habang nire-refresh.',
    'krj': 'Ginapakita ang kopya nga naka-save sa phone samtang gina-refresh.',
  },
  'No signal, and this record is not saved on this phone yet.': {
    'fil': 'Walang signal, at hindi pa naka-save ang rekord na ito sa phone na ito.',
    'krj': 'Wara it signal, kag wara pa naka-save ang rekord nga dya sa phone nga dya.',
  },
  'Land type saved.': {'fil': 'Na-save ang uri ng lupa.', 'krj': 'Na-save ang klase it duta.'},
  'Land type changed': {'fil': 'Binago ang uri ng lupa', 'krj': 'Ginbaylo ang klase it duta'},
  'Remove this treatment?': {'fil': 'Alisin ang lunas na ito?', 'krj': 'Kuhaon ang bulong nga dya?'},
  'Remove': {'fil': 'Alisin', 'krj': 'Kuhaon'},
  'Not sent': {'fil': 'Hindi naipadala', 'krj': 'Wara napadara'},
  'It is not sent again automatically. Fix the problem if you can, then try again.': {
    'fil': 'Hindi na ito kusang ipapadala ulit. Ayusin ang problema kung kaya, saka subukan ulit.',
    'krj': 'Indi run dya kusog nga ipadara liwan. Ayuha ang problema kon masarangan, dayon tilawan liwan.',
  },
  'Recommended by your technician': {'fil': 'Inirekomenda ng iyong technician', 'krj': 'Ginrekomendar it imo technician'},
  'Recommended by the reviewer': {'fil': 'Inirekomenda ng nagsuri', 'krj': 'Ginrekomendar it nag-usisa'},
  'Picked for this case from the approved options. These are recommendations, not treatments you applied.': {
    'fil': 'Pinili para sa kasong ito mula sa mga aprubadong opsyon. Mga rekomendasyon ito, hindi mga lunas na ginamit mo.',
    'krj': 'Ginpili para sa kaso nga dya halin sa mga aprubado nga opsyon. Mga rekomendasyon dya, indi mga bulong nga gin-gamit mo.',
  },
  'No longer approved': {'fil': 'Hindi na aprubado', 'krj': 'Indi run aprubado'},
  'Recommended by {name}': {'fil': 'Inirekomenda ni {name}', 'krj': 'Ginrekomendar ni {name}'},
  'Before': {'fil': 'Bago', 'krj': 'Antes'},
  'After': {'fil': 'Pagkatapos', 'krj': 'Pagkatapos'},
  'No follow-up photo yet. It is due now.': {
    'fil': 'Wala pang follow-up na litrato. Dapat na itong gawin ngayon.',
    'krj': 'Wara pa it follow-up nga litrato. Dapat run dya himuon makaron.',
  },
  'No follow-up photo yet.': {'fil': 'Wala pang follow-up na litrato.', 'krj': 'Wara pa it follow-up nga litrato.'},
  'Loading…': {'fil': 'Naglo-load…', 'krj': 'Gina-load…'},
  'Open the follow-up with signal to see it.': {
    'fil': 'Buksan ang follow-up kapag may signal para makita ito.',
    'krj': 'Buksi ang follow-up kon may signal para makita dya.',
  },
  'No pests detected on the follow-up photo — not yet confirmed by a technician': {
    'fil': 'Walang pesteng nakita sa follow-up na litrato — hindi pa kinukumpirma ng technician',
    'krj': 'Wara it peste nga nakita sa follow-up nga litrato — wara pa ginkumpirmar it technician',
  },
  'Follow-up waiting for review': {'fil': 'Naghihintay ng pagsusuri ang follow-up', 'krj': 'Nagahulat it pag-usisa ang follow-up'},
  'Open the follow-up': {'fil': 'Buksan ang follow-up', 'krj': 'Buksi ang follow-up'},

  // ---- lib/widgets/land_type_sheet.dart
  'Change the land type': {'fil': 'Baguhin ang uri ng lupa', 'krj': 'Bayluhan ang klase it duta'},
  'Pick what best describes this field. The change is saved with your name and the time.': {
    'fil': 'Piliin ang pinakaangkop sa bukid na ito. Ise-save ang pagbabago kasama ang iyong pangalan at oras.',
    'krj': 'Pilia ang pinakaangay sa uma nga dya. I-save ang pagbaylo upod ang imo ngaran kag oras.',
  },
  'Reason (optional)': {'fil': 'Dahilan (opsyonal)', 'krj': 'Rason (opsyonal)'},
  'Save land type': {'fil': 'I-save ang uri ng lupa', 'krj': 'I-save ang klase it duta'},
  'No signal. Changing the land type needs a connection; try again with signal.': {
    'fil': 'Walang signal. Kailangan ng koneksyon para baguhin ang uri ng lupa; subukan ulit kapag may signal.',
    'krj': 'Wara it signal. Kinahanglan it koneksyon para bayluhan ang klase it duta; tilawan liwan kon may signal.',
  },

  // ---- lib/screens/f27_guide.dart, lib/models/guide.dart
  'Detected by the photo model': {'fil': 'Nakikita ng photo model', 'krj': 'Nakita it photo model'},
  'Checked by people in the field': {'fil': 'Sinusuri ng tao sa bukid', 'krj': 'Ginausisa it tawo sa uma'},
  'Glossary': {'fil': 'Talahuluganan', 'krj': 'Glosaryo'},
  'Model label: {label}': {'fil': 'Label sa model: {label}', 'krj': 'Label sa model: {label}'},
  'Damage from {pest}': {'fil': 'Pinsala mula sa {pest}', 'krj': 'Danyos halin sa {pest}'},
  'Damage checkbox: {label}': {'fil': 'Checkbox ng pinsala: {label}', 'krj': 'Checkbox it danyos: {label}'},

  // ---- lib/screens/f25_notifications.dart
  'No signal, and no notifications are saved on this phone yet.': {
    'fil': 'Walang signal, at wala pang naka-save na abiso sa phone na ito.',
    'krj': 'Wara it signal, kag wara pa it naka-save nga pahibalo sa phone nga dya.',
  },
  'No signal. Showing the notifications saved on this phone.': {
    'fil': 'Walang signal. Ipinapakita ang mga abisong naka-save sa phone na ito.',
    'krj': 'Wara it signal. Ginapakita ang mga pahibalo nga naka-save sa phone nga dya.',
  },

  // ---- lib/screens/f60_validation_queue.dart
  "New observations waiting for your first review. Cases you escalate go to the agriculturist's To Be Validated queue.": {
    'fil': 'Mga bagong obserbasyon na naghihintay ng una mong pagsusuri. Ang mga kasong ipinasa mo ay mapupunta sa pila ng agriculturist na Ive-validate pa.',
    'krj': 'Mga bag-o nga obserbasyon nga nagahulat it una mo nga pag-usisa. Ang mga kaso nga ginpasa mo makadto sa pila it agriculturist nga I-validate pa.',
  },
  'No signal, and no list is saved on this phone yet.': {
    'fil': 'Walang signal, at wala pang naka-save na listahan sa phone na ito.',
    'krj': 'Wara it signal, kag wara pa it naka-save nga listahan sa phone nga dya.',
  },
  'Reason: {reason}': {'fil': 'Dahilan: {reason}', 'krj': 'Rason: {reason}'},
  'No technician covers this area': {'fil': 'Walang technician na sumasakop sa lugar na ito', 'krj': 'Wara it technician nga nagasakop sa lugar nga dya'},
  'Escalated by a technician': {'fil': 'Ipinasa ng technician', 'krj': 'Ginpasa it technician'},
  'Possibly unrelated photo': {'fil': 'Posibleng hindi kaugnay na litrato', 'krj': 'Basi indi angot nga litrato'},

  // ---- lib/screens/f61_review_observation.dart
  'No signal, and this report is not saved on this phone yet.': {
    'fil': 'Walang signal, at hindi pa naka-save ang ulat na ito sa phone na ito.',
    'krj': 'Wara it signal, kag wara pa naka-save ang report nga dya sa phone nga dya.',
  },
  'Reviewing needs a connection. Your decision is sent when you tap send with signal.': {
    'fil': 'Kailangan ng koneksyon sa pagsusuri. Maipapadala ang iyong desisyon kapag pinindot mo ang send habang may signal.',
    'krj': 'Kinahanglan it koneksyon sa pag-usisa. Mapadara ang imo desisyon kon pinduton mo ang send samtang may signal.',
  },
  'This photo may not show a rice plant or field. Check it before validating; return it if it is not a field photo.': {
    'fil': 'Maaaring hindi palay o bukid ang nasa litratong ito. Tingnan muna bago i-validate; ibalik kung hindi ito litrato ng bukid.',
    'krj': 'Basi indi humay ukon uma ang yara sa litrato nga dya. Turuka anay antes i-validate; ibalik kon indi dya litrato it uma.',
  },
  'Provisional thresholds: an agriculturist has not confirmed them yet. Use your own judgement for the level.': {
    'fil': 'Pansamantalang threshold: hindi pa ito kinukumpirma ng agriculturist. Gamitin ang sariling pagpapasya sa antas.',
    'krj': 'Temporaryo nga threshold: wara pa dya ginkumpirmar it agriculturist. Gamita ang kaugalingon mo nga paghukom sa lebel.',
  },
  'Reviewer note (required)': {'fil': 'Tala ng nagsuri (kailangan)', 'krj': 'Nota it nag-usisa (kinahanglan)'},
  'What you checked and why you chose this level': {
    'fil': 'Ano ang sinuri mo at bakit mo pinili ang antas na ito',
    'krj': 'Ano ang gin-usisa mo kag ham-an ginpili mo ang lebel nga dya',
  },
  'Kept in the review history for technicians and agriculturists. The farmer reads the guidance, not this note.': {
    'fil': 'Itinatago sa kasaysayan ng pagsusuri para sa mga technician at agriculturist. Ang gabay ang binabasa ng magsasaka, hindi ang talang ito.',
    'krj': 'Ginatago sa kasaysayan it pag-usisa para sa mga technician kag agriculturist. Ang giya ang ginabasa it mangunguma, indi ang nota nga dya.',
  },
  'Recommendations (not applied treatments)': {
    'fil': 'Mga rekomendasyon (hindi mga lunas na nagamit)',
    'krj': 'Mga rekomendasyon (indi mga bulong nga nagamit)',
  },
  'Optional. Pick approved options for this pest to recommend to the farmer. They show as recommendations, not as treatments the farmer applied.': {
    'fil': 'Opsyonal. Pumili ng mga aprubadong opsyon para sa pesteng ito na irerekomenda sa magsasaka. Lalabas ang mga ito bilang rekomendasyon, hindi bilang lunas na ginamit ng magsasaka.',
    'krj': 'Opsyonal. Magpili it mga aprubado nga opsyon para sa peste nga dya nga irekomendar sa mangunguma. Magguwa dya bilang rekomendasyon, indi bilang bulong nga gin-gamit it mangunguma.',
  },
  'No approved options for this pest yet.': {
    'fil': 'Wala pang aprubadong opsyon para sa pesteng ito.',
    'krj': 'Wara pa it aprubado nga opsyon para sa peste nga dya.',
  },
  'Recommendations': {'fil': 'Mga rekomendasyon', 'krj': 'Mga rekomendasyon'},
};
