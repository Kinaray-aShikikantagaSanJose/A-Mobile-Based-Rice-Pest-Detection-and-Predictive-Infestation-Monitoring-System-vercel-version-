// Translations (auth). Key = the English text used in the code.
// Each entry: {'fil': 'Filipino', 'krj': 'Kinaray-a (Antique)'}. Keep {placeholders} unchanged.
const Map<String, Map<String, String>> kAuthStrings = {
  // ---- Splash / welcome (f10) ----
  'Rice Pest Detection, Infestation Hotspot Monitoring, Treatment Recommendation, and Trend Prediction System': {
    'fil': 'Sistema sa pagtukoy ng peste sa palay, pagbabantay ng hotspot, payo sa lunas, at prediksyon ng trend',
    'krj': 'Sistema sa pagkilala it peste sa humay, pagbantay it hotspot, tambag sa bulong, kag prediksyon it trend',
  },
  'Log In': {'fil': 'Mag-log in', 'krj': 'Mag-log in'},
  'Get Started': {'fil': 'Magsimula', 'krj': 'Magsugod'},
  'Create Account': {'fil': 'Gumawa ng account', 'krj': 'Maghimo it account'},
  'I already have an account': {'fil': 'May account na ako', 'krj': 'May account run ako'},

  // ---- Onboarding tour (f01) ----
  'Skip': {'fil': 'Laktawan', 'krj': 'I-skip'},
  'Next': {'fil': 'Susunod', 'krj': 'Sunod'},
  'Pest Identification (Model Result)': {
    'fil': 'Pagkilala ng peste (Resulta ng AI)',
    'krj': 'Pagkilala it peste (Resulta it AI)',
  },
  'Capture field images to detect supported pests, crop stages, and infestation indications in seconds.': {
    'fil': 'Kunan ng litrato ang palayan para malaman agad ang peste, yugto ng palay, at antas ng peste sa loob ng ilang segundo.',
    'krj': 'Kuhaan it litrato ang uma para mahibaruan dayon ang peste, edad it humay, kag lebel it peste sa pila lang ka segundo.',
  },
  'Expert Validation': {'fil': 'Pagsusuri ng eksperto', 'krj': 'Pag-usisa it eksperto'},
  'Send field data to agricultural technicians to verify diagnoses and receive custom management recommendations.': {
    'fil': 'Ipadala ang datos ng palayan sa mga technician para ma-check ang resulta at makakuha ng payo para sa iyong bukid.',
    'krj': 'Ipadara ang datos it uma sa mga technician para ma-check ang resulta kag makabaton it tambag para sa imo nga uma.',
  },
  'Hotspots and Field Trends': {'fil': 'Mga hotspot at trend sa bukid', 'krj': 'Mga hotspot kag trend sa uma'},
  'Track treatment outcomes, monitor localized hotspot maps, and view quarterly pest trend advisories.': {
    'fil': 'Bantayan ang resulta ng lunas, tingnan ang mapa ng mga hotspot sa inyong lugar, at ang payo sa trend ng peste kada quarter.',
    'krj': 'Bantayan ang resulta it bulong, turuka ang mapa it mga hotspot sa inyo nga lugar, kag ang tambag parti sa trend it peste kada quarter.',
  },

  // ---- Email verification (f11b) ----
  'Back': {'fil': 'Bumalik', 'krj': 'Balik'},
  'Verify': {'fil': 'I-verify', 'krj': 'I-verify'},
  'Verify Your Account': {'fil': 'I-verify ang iyong account', 'krj': 'I-verify ang imo nga account'},
  'Enter the 6-digit code sent to {email} to continue.': {
    'fil': 'Ilagay ang 6-digit na code na ipinadala sa {email} para magpatuloy.',
    'krj': 'Isulat ang 6-digit nga code nga ginpadara sa {email} para makapadayon.',
  },
  'your email': {'fil': 'iyong email', 'krj': 'imo nga email'},
  "Didn't receive the code?": {'fil': 'Hindi natanggap ang code?', 'krj': 'Wara nabaton ang code?'},
  'Sending...': {'fil': 'Ipinapadala...', 'krj': 'Ginapadara...'},
  'Resend in {time}': {'fil': 'Ipadala ulit sa {time}', 'krj': 'Ipadara liwan sa {time}'},
  'Resend code': {'fil': 'Ipadala ulit ang code', 'krj': 'Ipadara liwan ang code'},
  'Enter the complete 6-digit code.': {
    'fil': 'Ilagay ang buong 6-digit na code.',
    'krj': 'Isulat ang bilog nga 6-digit nga code.',
  },
  'Email verified. Please log in.': {
    'fil': 'Na-verify na ang email. Mag-log in na.',
    'krj': 'Na-verify run ang email. Palihog mag-log in.',
  },
  'Email verified.': {'fil': 'Na-verify na ang email.', 'krj': 'Na-verify run ang email.'},
  'New code sent.': {'fil': 'Naipadala na ang bagong code.', 'krj': 'Napadara run ang bag-o nga code.'},

  // ---- Login (f12a) ----
  'Welcome Back': {'fil': 'Maligayang pagbabalik', 'krj': 'Mayad nga pagbalik'},
  'Report pests, follow treatments and keep your field healthy.': {
    'fil': 'Mag-report ng peste, sundin ang lunas, at alagaan nang mabuti ang iyong palayan.',
    'krj': 'Mag-report it peste, sunda ang bulong, kag atipana it mayad ang imo nga uma.',
  },
  'Sign in': {'fil': 'Mag-log in', 'krj': 'Mag-log in'},
  'Log in with the email you registered with': {
    'fil': 'Mag-log in gamit ang email na ginamit mo sa pagparehistro',
    'krj': 'Mag-log in gamit ang email nga gin-gamit mo sa pagparehistro',
  },
  'Your session expired. Please log in again.': {
    'fil': 'Nag-expire na ang iyong session. Mag-log in ulit.',
    'krj': 'Nag-expire run ang imo nga session. Palihog mag-log in liwan.',
  },
  'Email address': {'fil': 'Email address', 'krj': 'Email address'},
  'Password': {'fil': 'Password', 'krj': 'Password'},
  'Show password': {'fil': 'Ipakita ang password', 'krj': 'Ipakita ang password'},
  'Hide password': {'fil': 'Itago ang password', 'krj': 'Itago ang password'},
  'Forgot password?': {'fil': 'Nakalimutan ang password?', 'krj': 'Nalipatan ang password?'},
  'Logging in...': {'fil': 'Nagla-log in...', 'krj': 'Naga-log in...'},
  "Don't have an account?": {'fil': 'Wala ka pang account?', 'krj': 'Wara ka pa it account?'},
  'Sign Up': {'fil': 'Magparehistro', 'krj': 'Magparehistro'},
  'For farmers and agricultural technicians': {
    'fil': 'Para sa mga magsasaka at technician',
    'krj': 'Para sa mga mangunguma kag technician',
  },
  'Enter your email and password.': {
    'fil': 'Ilagay ang iyong email at password.',
    'krj': 'Isulat ang imo nga email kag password.',
  },
  'Enter a valid email address.': {
    'fil': 'Maglagay ng tamang email address.',
    'krj': 'Magsulat it husto nga email address.',
  },
  'Something went wrong. Please try again.': {
    'fil': 'May nagkaproblema. Subukan ulit.',
    'krj': 'May problema. Tilawan liwan.',
  },
  'Agriculturist accounts use the Palay Patrol web dashboard. Sign in there with the same email and password.': {
    'fil': 'Ang mga account ng agriculturist ay para sa Palay Patrol web dashboard. Doon mag-log in gamit ang parehong email at password.',
    'krj': 'Ang mga account it agriculturist para sa Palay Patrol web dashboard. Mag-log in rugto gamit ang pareho nga email kag password.',
  },
  'Sign-in failed: the server did not return a session. Please try again.': {
    'fil': 'Hindi naka-log in: walang ibinalik na session ang server. Subukan ulit.',
    'krj': 'Indi naka-log in: wara it session nga ginbalik ang server. Tilawan liwan.',
  },
  'Connected to the server': {'fil': 'Konektado sa server', 'krj': 'Konektado sa server'},
  'Searching this network; sync will resume automatically.': {
    'fil': 'Naghahanap sa network na ito; kusang magpapatuloy ang sync.',
    'krj': 'Nagapangita sa network nga kadya; automatic nga magapadayon ang sync.',
  },
  'Finding the server on Wi-Fi, Ethernet, or hotspot…': {
    'fil': 'Hinahanap ang server sa Wi-Fi, Ethernet, o hotspot…',
    'krj': 'Ginapangita ang server sa Wi-Fi, Ethernet, ukon hotspot…',
  },
  'Keep this device on the same local network as the server. The app retries discovery automatically.': {
    'fil': 'Dapat nasa parehong local network ng server ang device na ito. Kusang hahanapin ulit ng app ang server.',
    'krj': 'Dapat yara ang device nga kadya sa pareho nga local network it server. Automatic nga ginapangita liwan it app ang server.',
  },
  'Sending code...': {'fil': 'Ipinapadala ang code...', 'krj': 'Ginapadara ang code...'},
  'Verify my email': {'fil': 'I-verify ang email ko', 'krj': 'I-verify ang akon nga email'},
  'We sent a new verification code to {email}.': {
    'fil': 'Nagpadala kami ng bagong verification code sa {email}.',
    'krj': 'Nagpadara kami it bag-o nga verification code sa {email}.',
  },
  'Use the code we sent to {email} a moment ago.': {
    'fil': 'Gamitin ang code na ipinadala namin sa {email} kanina lang.',
    'krj': 'Gamiton ang code nga ginpadara namon sa {email} kaina lang.',
  },
  'Reset your password': {'fil': 'I-reset ang iyong password', 'krj': 'I-reset ang imo nga password'},
  'Password resets are handled by your local agriculture office. Contact your Municipal Agriculture Office or your assigned agricultural technician and they will help you regain access to your account.': {
    'fil': 'Ang pag-reset ng password ay ginagawa ng inyong agriculture office. Kontakin ang inyong Municipal Agriculture Office o ang technician na naka-assign sa inyo, at tutulungan ka nilang makapasok ulit sa iyong account.',
    'krj': 'Ang pag-reset it password ginahimo it inyo nga agriculture office. Kontaka ang inyo nga Municipal Agriculture Office ukon ang technician nga naka-assign sa inyo, kag buligan ka nanda nga makasulod liwan sa imo nga account.',
  },
  'Got it': {'fil': 'Sige', 'krj': 'Sige'},

  // ---- Waiting for approval (f14) ----
  'Waiting for approval': {'fil': 'Naghihintay ng approval', 'krj': 'Nagahulat it approval'},
  'Your account was not approved': {
    'fil': 'Hindi naaprubahan ang iyong account',
    'krj': 'Wara na-approve ang imo nga account',
  },
  "Your email is verified. An agriculturist from your municipal agriculture office will check and approve your account. You can close the app; we'll let you in as soon as it's approved.": {
    'fil': 'Na-verify na ang iyong email. Susuriin at aaprubahan ng isang agriculturist mula sa inyong municipal agriculture office ang iyong account. Puwede mong isara ang app; papapasukin ka namin agad kapag approved na.',
    'krj': 'Na-verify run ang imo nga email. Ang agriculturist halin sa inyo nga municipal agriculture office ang mag-usisa kag mag-approve it imo nga account. Pwede mo sirhan ang app; pasudlon ka namon dayon kon approved run.',
  },
  'Please visit or call your Municipal Agriculture Office if you think this is a mistake.': {
    'fil': 'Pumunta o tumawag sa inyong Municipal Agriculture Office kung sa tingin mo ay may mali.',
    'krj': 'Palihog magkadto ukon magtawag sa inyo nga Municipal Agriculture Office kon sa imo hunahuna may sala.',
  },
  'Requested role: Agricultural technician': {
    'fil': 'Hiniling na tungkulin: Agricultural technician',
    'krj': 'Gin-request nga role: Agricultural technician',
  },
  'Requested role: Agriculturist': {
    'fil': 'Hiniling na tungkulin: Agriculturist',
    'krj': 'Gin-request nga role: Agriculturist',
  },
  'Requested role: Farmer': {
    'fil': 'Hiniling na tungkulin: Magsasaka',
    'krj': 'Gin-request nga role: Mangunguma',
  },
  'Check again': {'fil': 'I-check ulit', 'krj': 'I-check liwan'},
  "Not approved yet. We'll keep checking.": {
    'fil': 'Hindi pa approved. Patuloy kaming magche-check.',
    'krj': 'Indi pa approved. Padayon kami nga magcheck.',
  },
  'Sign out': {'fil': 'Mag-log out', 'krj': 'Mag-log out'},

  // ---- Server messages shown on the login / verification screens ----
  'Invalid email or password.': {'fil': 'Mali ang email o password.', 'krj': 'Sala ang email ukon password.'},
  'Please verify your email before logging in.': {
    'fil': 'I-verify muna ang iyong email bago mag-log in.',
    'krj': 'I-verify anay ang imo nga email antes mag-log in.',
  },
  'Invalid verification code.': {'fil': 'Mali ang verification code.', 'krj': 'Sala ang verification code.'},
  'Verification code has expired.': {
    'fil': 'Nag-expire na ang verification code.',
    'krj': 'Nag-expire run ang verification code.',
  },
  'Too many incorrect attempts. Please request a new code.': {
    'fil': 'Masyadong maraming maling subok. Humingi ng bagong code.',
    'krj': 'Madamo run nga sala nga tilaw. Palihog mangayo it bag-o nga code.',
  },
};
