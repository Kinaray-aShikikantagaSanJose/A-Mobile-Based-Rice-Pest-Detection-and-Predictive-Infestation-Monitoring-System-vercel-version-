// Translations (profile: registration and profile screens).
// Key = the English text used in the code.
// Each entry: {'fil': 'Filipino', 'krj': 'Kinaray-a (Antique)'}. Keep {placeholders} unchanged.
const Map<String, Map<String, String>> kProfileStrings = {
  // ---- registration (f11a)
  'Select Your Role': {'fil': 'Piliin ang Iyong Tungkulin', 'krj': 'Pilia ang Imo nga Role'},
  'Choose how you will use the app.': {'fil': 'Piliin kung paano mo gagamitin ang app.', 'krj': 'Pilia kon paano mo gamiton ang app.'},
  "I'm a Farmer": {'fil': 'Magsasaka ako', 'krj': 'Mangunguma ako'},
  'Report pests and diseases, get treatment options and reminders.': {
    'fil': 'Mag-ulat ng peste at sakit, makakuha ng mga lunas at paalala.',
    'krj': 'Mag-report it peste kag balatian, makakuha it mga bulong kag pahanumdom.',
  },
  'Agricultural Technician': {'fil': 'Agricultural Technician', 'krj': 'Agricultural Technician'},
  'Everything farmers have, plus validation, infestation levels, escalation and the local map.': {
    'fil': 'Lahat ng mayroon ang magsasaka, dagdag ang validation, antas ng peste, pagpasa sa agriculturist at lokal na mapa.',
    'krj': 'Tanan nga yara sa mangunguma, dugang ang validation, lebel it peste, pagpasa sa agriculturist kag lokal nga mapa.',
  },
  'Agriculturists and OPA staff use the Palay Patrol web dashboard.': {
    'fil': 'Ang mga agriculturist at staff ng OPA ay gumagamit ng Palay Patrol web dashboard.',
    'krj': 'Ang mga agriculturist kag staff it OPA gagamit it Palay Patrol web dashboard.',
  },
  'Back to role selection': {'fil': 'Bumalik sa pagpili ng tungkulin', 'krj': 'Balik sa pagpili it role'},
  'Create your account': {'fil': 'Gumawa ng iyong account', 'krj': 'Maghimo it imo nga account'},
  'Registering as a Farmer. Your municipal agriculture office will check your details and confirm your role before your account can be used.': {
    'fil':
        'Nagpaparehistro bilang Magsasaka. Susuriin ng municipal agriculture office ang iyong detalye at kukumpirmahin ang iyong tungkulin bago magamit ang account.',
    'krj':
        'Nagaparehistro bilang Mangunguma. Usisaon it municipal agriculture office ang imo nga detalye kag kumpirmahon ang imo nga role antes magamit ang account.',
  },
  'Registering as an Agricultural Technician. Your municipal agriculture office will check your details and confirm your role before your account can be used.': {
    'fil':
        'Nagpaparehistro bilang Agricultural Technician. Susuriin ng municipal agriculture office ang iyong detalye at kukumpirmahin ang iyong tungkulin bago magamit ang account.',
    'krj':
        'Nagaparehistro bilang Agricultural Technician. Usisaon it municipal agriculture office ang imo nga detalye kag kumpirmahon ang imo nga role antes magamit ang account.',
  },
  'Full name': {'fil': 'Buong pangalan', 'krj': 'Bug-os nga ngaran'},
  'e.g. Juan A. Dela Cruz': {'fil': 'hal. Juan A. Dela Cruz', 'krj': 'pananglitan Juan A. Dela Cruz'},
  'Enter your full name.': {'fil': 'Ilagay ang iyong buong pangalan.', 'krj': 'Ibutang ang imo nga bug-os nga ngaran.'},
  'Email': {'fil': 'Email', 'krj': 'Email'},
  'e.g. juan.delacruz@gmail.com': {'fil': 'hal. juan.delacruz@gmail.com', 'krj': 'pananglitan juan.delacruz@gmail.com'},
  'Enter a valid email address.': {'fil': 'Maglagay ng tamang email address.', 'krj': 'Magbutang it husto nga email address.'},
  'Mobile number': {'fil': 'Numero ng cellphone', 'krj': 'Numero it cellphone'},
  'e.g. 0917 123 4567': {'fil': 'hal. 0917 123 4567', 'krj': 'pananglitan 0917 123 4567'},
  'Enter a valid mobile number.': {'fil': 'Maglagay ng tamang numero ng cellphone.', 'krj': 'Magbutang it husto nga numero it cellphone.'},
  'At least 8 characters': {'fil': 'Hindi bababa sa 8 karakter', 'krj': 'Indi magnubo sa 8 ka karakter'},
  'Password must be at least 8 characters.': {
    'fil': 'Dapat hindi bababa sa 8 karakter ang password.',
    'krj': 'Dapat indi magnubo sa 8 ka karakter ang password.',
  },
  'Confirm password': {'fil': 'Kumpirmahin ang password', 'krj': 'Kumpirmaha ang password'},
  'Re-enter your password': {'fil': 'Ilagay ulit ang password', 'krj': 'Ibutang liwan ang password'},
  'Passwords do not match.': {'fil': 'Hindi magkapareho ang mga password.', 'krj': 'Indi pareho ang mga password.'},
  'Barangay': {'fil': 'Barangay', 'krj': 'Barangay'},
  'e.g. Poblacion': {'fil': 'hal. Poblacion', 'krj': 'pananglitan Poblacion'},
  'Enter your barangay.': {'fil': 'Ilagay ang iyong barangay.', 'krj': 'Ibutang ang imo nga barangay.'},
  'Municipality': {'fil': 'Munisipyo', 'krj': 'Banwa'},
  'Select your municipality': {'fil': 'Piliin ang iyong munisipyo', 'krj': 'Pilia ang imo nga banwa'},
  'Select your municipality.': {'fil': 'Piliin ang iyong munisipyo.', 'krj': 'Pilia ang imo nga banwa.'},
  'Please select your municipality.': {'fil': 'Pakipili ang iyong munisipyo.', 'krj': 'Palihog pilia ang imo nga banwa.'},
  'I agree to the Terms & Privacy Policy': {'fil': 'Sumasang-ayon ako sa Terms at Privacy Policy', 'krj': 'Nagasugot ako sa Terms kag Privacy Policy'},
  'Please agree to the Terms & Privacy Policy.': {
    'fil': 'Pakisang-ayunan ang Terms at Privacy Policy.',
    'krj': 'Palihog sugti ang Terms kag Privacy Policy.',
  },
  'Continue': {'fil': 'Magpatuloy', 'krj': 'Padayon'},
  'Already have an account?': {'fil': 'May account ka na?', 'krj': 'May account ka run?'},
  'Log In': {'fil': 'Mag-log in', 'krj': 'Mag-log in'},
  'Verification code sent to {email}.': {
    'fil': 'Naipadala ang verification code sa {email}.',
    'krj': 'Napadara run ang verification code sa {email}.',
  },
  'Show password': {'fil': 'Ipakita ang password', 'krj': 'Ipakita ang password'},
  'Hide password': {'fil': 'Itago ang password', 'krj': 'Itago ang password'},
  'Password': {'fil': 'Password', 'krj': 'Password'},

  // ---- profile (f15)
  'My profile': {'fil': 'Aking profile', 'krj': 'Akon nga profile'},
  'Back': {'fil': 'Bumalik', 'krj': 'Balik'},
  'Change profile picture': {'fil': 'Palitan ang profile picture', 'krj': 'Bayluhan ang profile picture'},
  'Personal information': {'fil': 'Personal na impormasyon', 'krj': 'Personal nga impormasyon'},
  'Set by your agriculturist (it decides your queue).': {
    'fil': 'Itinakda ng iyong agriculturist (ito ang nagpapasya ng iyong pila).',
    'krj': 'Ginbutang it imo nga agriculturist (amo dya ang nagadesisyon it imo nga pila).',
  },
  'Not set': {'fil': 'Wala pa', 'krj': 'Wara pa'},
  'Not set yet': {'fil': 'Wala pang nakatakda', 'krj': 'Wara pa nabutang'},
  'All of {municipality}': {'fil': 'Buong {municipality}', 'krj': 'Bug-os nga {municipality}'},
  'Coverage': {'fil': 'Sakop', 'krj': 'Sakop'},
  'Save changes': {'fil': 'I-save ang mga pagbabago', 'krj': 'I-save ang mga pagbag-o'},
  'Enter your mobile number.': {'fil': 'Ilagay ang iyong numero ng cellphone.', 'krj': 'Ibutang ang imo nga numero it cellphone.'},
  'Enter a valid mobile number, e.g. 0917 123 4567.': {
    'fil': 'Maglagay ng tamang numero ng cellphone, hal. 0917 123 4567.',
    'krj': 'Magbutang it husto nga numero it cellphone, pananglitan 0917 123 4567.',
  },
  'Choose your municipality.': {'fil': 'Piliin ang iyong munisipyo.', 'krj': 'Pilia ang imo nga banwa.'},
  'Profile saved.': {'fil': 'Na-save ang profile.', 'krj': 'Na-save run ang profile.'},
  'No signal. Showing the profile saved on this phone.': {
    'fil': 'Walang signal. Ipinapakita ang profile na naka-save sa teleponong ito.',
    'krj': 'Wara it signal. Ginapakita ang profile nga naka-save sa telepono nga kadya.',
  },
  'No signal. Your changes were not saved; try again with signal.': {
    'fil': 'Walang signal. Hindi na-save ang mga pagbabago; subukan ulit kapag may signal.',
    'krj': 'Wara it signal. Wara na-save ang mga pagbag-o; tilawan liwan kon may signal run.',
  },
  'Change password': {'fil': 'Palitan ang password', 'krj': 'Bayluhan ang password'},
  'Current password': {'fil': 'Kasalukuyang password', 'krj': 'Password makaron'},
  'New password': {'fil': 'Bagong password', 'krj': 'Bag-o nga password'},
  'Type the new password again': {'fil': 'I-type ulit ang bagong password', 'krj': 'I-type liwan ang bag-o nga password'},
  'Update password': {'fil': 'I-update ang password', 'krj': 'I-update ang password'},
  'Enter your current password.': {'fil': 'Ilagay ang kasalukuyang password.', 'krj': 'Ibutang ang password mo makaron.'},
  'Use at least 8 characters.': {'fil': 'Gumamit ng hindi bababa sa 8 karakter.', 'krj': 'Gamit it indi magnubo sa 8 ka karakter.'},
  "The passwords don't match.": {'fil': 'Hindi magkapareho ang mga password.', 'krj': 'Indi pareho ang mga password.'},
  'Password changed. Use the new one the next time you sign in.': {
    'fil': 'Napalitan ang password. Gamitin ang bago sa susunod na pag-log in.',
    'krj': 'Nabaylo run ang password. Gamiton ang bag-o sa masunod nga pag-log in.',
  },
  'No signal. The password was not changed.': {
    'fil': 'Walang signal. Hindi napalitan ang password.',
    'krj': 'Wara it signal. Wara nabaylo ang password.',
  },
  'Profile picture': {'fil': 'Profile picture', 'krj': 'Profile picture'},
  'Take a photo': {'fil': 'Kumuha ng litrato', 'krj': 'Magkuha it litrato'},
  'Choose from gallery': {'fil': 'Pumili sa gallery', 'krj': 'Mamili sa gallery'},
  'Remove picture': {'fil': 'Alisin ang larawan', 'krj': 'Kuhaa ang litrato'},
  'Could not open the camera.': {'fil': 'Hindi mabuksan ang camera.', 'krj': 'Indi mabuksan ang camera.'},
  'Could not open the gallery.': {'fil': 'Hindi mabuksan ang gallery.', 'krj': 'Indi mabuksan ang gallery.'},
  'Profile picture updated.': {'fil': 'Na-update ang profile picture.', 'krj': 'Na-update run ang profile picture.'},
  'No signal. The picture was not uploaded.': {
    'fil': 'Walang signal. Hindi na-upload ang larawan.',
    'krj': 'Wara it signal. Wara na-upload ang litrato.',
  },
  'Profile picture removed.': {'fil': 'Inalis ang profile picture.', 'krj': 'Ginkuha run ang profile picture.'},
  'No signal. Try again with signal.': {
    'fil': 'Walang signal. Subukan ulit kapag may signal.',
    'krj': 'Wara it signal. Tilawan liwan kon may signal run.',
  },
  'Pull down to load changes made by your agriculturist.': {
    'fil': 'Hilahin pababa para makita ang mga pagbabago ng iyong agriculturist.',
    'krj': 'Gubuta pababa para makita ang mga pagbag-o it imo nga agriculturist.',
  },
};
