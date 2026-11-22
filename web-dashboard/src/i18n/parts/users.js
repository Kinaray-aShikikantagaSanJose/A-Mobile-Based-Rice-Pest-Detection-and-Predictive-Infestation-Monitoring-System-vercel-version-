// Translations for the dashboard (users). Key = the English text used in the code.
// Each entry: { fil: 'Filipino', krj: 'Kinaray-a (Antique)' }. Keep {placeholders} unchanged.
export default {
  // ---------------------------------------------------------------- roles, statuses, shared labels
  Farmer: { fil: 'Magsasaka', krj: 'Mangunguma' },
  Technician: { fil: 'Technician', krj: 'Technician' },
  Agriculturist: { fil: 'Agriculturist', krj: 'Agriculturist' },
  Pending: { fil: 'Naghihintay', krj: 'Nagahulat' },
  Approved: { fil: 'Aprubado', krj: 'Aprubado' },
  Rejected: { fil: 'Tinanggihan', krj: 'Ginbalibaran' },
  Escalated: { fil: 'Ipinasa sa agriculturist', krj: 'Ginpasa sa agriculturist' },
  Unassigned: { fil: 'Hindi nakatalaga', krj: 'Wara natoka' },
  Municipality: { fil: 'Munisipyo', krj: 'Banwa' },
  Barangay: { fil: 'Barangay', krj: 'Barangay' },
  All: { fil: 'Lahat', krj: 'Tanan' },
  Role: { fil: 'Tungkulin', krj: 'Role' },
  Status: { fil: 'Status', krj: 'Status' },
  Email: { fil: 'Email', krj: 'Email' },
  Search: { fil: 'Maghanap', krj: 'Mangita' },
  Edit: { fil: 'I-edit', krj: 'I-edit' },
  Cancel: { fil: 'Kanselahin', krj: 'Indi lang' },
  'Mobile number': { fil: 'Numero ng cellphone', krj: 'Numero it cellphone' },
  'Not set': { fil: 'Hindi pa nakatakda', krj: 'Wara pa ginbutang' },
  'No phone': { fil: 'Walang numero', krj: 'Wara it numero' },
  'Coverage barangays': { fil: 'Mga sakop na barangay', krj: 'Mga sakop nga barangay' },
  'Whole municipality': { fil: 'Buong munisipyo', krj: 'Bilog nga banwa' },
  "Coverage = municipality + barangays. Leave barangays empty to cover the whole municipality. Observations reach the queue of each technician whose coverage includes the farmer's barangay.":
    {
      fil: 'Sakop = munisipyo + mga barangay. Iwanang blangko ang barangay para masakop ang buong munisipyo. Napupunta ang mga obserbasyon sa pila ng bawat technician na sakop ang barangay ng magsasaka.',
      krj: 'Sakop = banwa + mga barangay. Pabay-i nga blangko ang barangay para masakop ang bilog nga banwa. Ang mga obserbasyon makadto sa pila it kada technician nga sakop ang barangay it mangunguma.',
    },

  // ---------------------------------------------------------------- approval queue
  '{name} approved as {role}.': { fil: 'Naaprubahan si {name} bilang {role}.', krj: 'Gin-aprubahan si {name} bilang {role}.' },
  "Reject {name}'s account? They won't be able to use the app or dashboard.": {
    fil: 'Tanggihan ang account ni {name}? Hindi na niya magagamit ang app o dashboard.',
    krj: 'Balibaran ang account ni {name}? Indi run magamit ang app ukon dashboard.',
  },
  "{name}'s account was rejected.": { fil: 'Tinanggihan ang account ni {name}.', krj: 'Ginbalibaran ang account ni {name}.' },
  'Requested: {role}': { fil: 'Hiniling: {role}', krj: 'Ginpangayo: {role}' },
  'No area given': { fil: 'Walang nakasaad na lugar', krj: 'Wara it ginbutang nga lugar' },
  'Requested {date}': { fil: 'Humiling noong {date}', krj: 'Nagpangayo kang {date}' },
  'Approve as': { fil: 'Aprubahan bilang', krj: 'Aprubahan bilang' },
  Approve: { fil: 'Aprubahan', krj: 'Aprubahan' },
  Reject: { fil: 'Tanggihan', krj: 'Balibaran' },
  'Approval queue ({n})': { fil: 'Naghihintay ng pag-apruba ({n})', krj: 'Nagahulat it pag-apruba ({n})' },
  "New accounts can't use the app or dashboard until you approve them. Each person picks a role when registering; confirm it or change it here before approving.":
    {
      fil: "Hindi magagamit ng mga bagong account ang app o dashboard hangga't hindi mo sila inaaprubahan. Pumipili ng tungkulin ang bawat isa pagparehistro; kumpirmahin o palitan ito dito bago aprubahan.",
      krj: 'Indi magamit it mga bag-o nga account ang app ukon dashboard hasta indi mo sanda ma-aprubahan. Kada isara nagapili it role pag-register; kumpirmaha ukon ilisan diya antes mag-aprubar.',
    },
  'No accounts waiting for approval': {
    fil: 'Walang account na naghihintay ng pag-apruba',
    krj: 'Wara it account nga nagahulat it pag-apruba',
  },
  '{n} more account hasn’t verified their email yet. They appear here once they do.': {
    fil: 'May {n} pang account na hindi pa na-verify ang email. Lalabas sila dito kapag na-verify na.',
    krj: 'May {n} pa nga account nga wara pa na-verify ang email. Magaguwa sanda diya kon ma-verify run.',
  },
  '{n} more accounts haven’t verified their email yet. They appear here once they do.': {
    fil: 'May {n} pang account na hindi pa na-verify ang email. Lalabas sila dito kapag na-verify na.',
    krj: 'May {n} pa nga account nga wara pa na-verify ang email. Magaguwa sanda diya kon ma-verify run.',
  },

  // ---------------------------------------------------------------- add / edit an account
  'Choose a picture file (JPG or PNG).': { fil: 'Pumili ng file ng litrato (JPG o PNG).', krj: 'Magpili it file it litrato (JPG ukon PNG).' },
  'That picture is larger than 8 MB.': { fil: 'Lampas sa 8 MB ang litratong iyan.', krj: 'Mas dako sa 8 MB ang litrato nga kato.' },
  'Enter the full name.': { fil: 'Ilagay ang buong pangalan.', krj: 'Ibutang ang bilog nga ngaran.' },
  'Enter a valid email address.': { fil: 'Maglagay ng tamang email address.', krj: 'Magbutang it husto nga email address.' },
  'Enter the mobile number.': { fil: 'Ilagay ang numero ng cellphone.', krj: 'Ibutang ang numero it cellphone.' },
  'Enter a valid mobile number, e.g. 0917 123 4567.': {
    fil: 'Maglagay ng tamang numero ng cellphone, hal. 0917 123 4567.',
    krj: 'Magbutang it husto nga numero it cellphone, hal. 0917 123 4567.',
  },
  'Choose the municipality.': { fil: 'Piliin ang munisipyo.', krj: 'Pilia ang banwa.' },
  'Enter the barangay.': { fil: 'Ilagay ang barangay.', krj: 'Ibutang ang barangay.' },
  'The password needs at least 8 characters.': {
    fil: 'Kailangan ng hindi bababa sa 8 character ang password.',
    krj: 'Kinahanglan it indi magnubo sa 8 ka character ang password.',
  },
  'The new password needs at least 8 characters.': {
    fil: 'Kailangan ng hindi bababa sa 8 character ang bagong password.',
    krj: 'Kinahanglan it indi magnubo sa 8 ka character ang bag-o nga password.',
  },
  'Please fix the highlighted field before saving.': {
    fil: 'Ayusin muna ang naka-highlight na field bago i-save.',
    krj: 'Ayusa anay ang naka-highlight nga field antes i-save.',
  },
  'Please fix the {n} highlighted fields before saving.': {
    fil: 'Ayusin muna ang {n} naka-highlight na field bago i-save.',
    krj: 'Ayusa anay ang {n} ka naka-highlight nga field antes i-save.',
  },
  "{name}'s account was created.": { fil: 'Nagawa na ang account ni {name}.', krj: 'Nahimo run ang account ni {name}.' },
  '{name} updated.': { fil: 'Na-update si {name}.', krj: 'Na-update si {name}.' },
  "{name}'s account was deleted.": { fil: 'Nabura na ang account ni {name}.', krj: 'Napanas run ang account ni {name}.' },
  "You can't change your own role or approval": {
    fil: 'Hindi mo mapapalitan ang sarili mong tungkulin o pag-apruba',
    krj: 'Indi mo mailisan ang imo kaugalingon nga role ukon pag-apruba',
  },
  'Add an account': { fil: 'Magdagdag ng account', krj: 'Magdugang it account' },
  'Edit account': { fil: 'I-edit ang account', krj: 'I-edit ang account' },
  'Active right away: no email code needed.': {
    fil: 'Aktibo agad: hindi kailangan ng code sa email.',
    krj: 'Aktibo dayon: indi kinahanglan it code sa email.',
  },
  'Profile picture': { fil: 'Litrato sa profile', krj: 'Litrato sa profile' },
  'Change picture': { fil: 'Palitan ang litrato', krj: 'Ilisan ang litrato' },
  'Upload picture': { fil: 'I-upload ang litrato', krj: 'I-upload ang litrato' },
  Remove: { fil: 'Alisin', krj: 'Kuhaa' },
  'JPG or PNG, up to 8 MB. Cropped to a square.': {
    fil: 'JPG o PNG, hanggang 8 MB. Gagawing parisukat.',
    krj: 'JPG ukon PNG, hasta 8 MB. Himuon nga kwadrado.',
  },
  'Full name *': { fil: 'Buong pangalan *', krj: 'Bilog nga ngaran *' },
  'Email *': { fil: 'Email *', krj: 'Email *' },
  "The email is the sign-in name and links the person's records, so it can't be changed.": {
    fil: 'Ang email ang ginagamit sa pag-log in at nag-uugnay sa mga rekord ng tao, kaya hindi ito mapapalitan.',
    krj: 'Ang email ang ginagamit sa pag-log in kag nagaugnay sa mga rekord it tawo, gani indi kadya mailisan.',
  },
  'Mobile number *': { fil: 'Numero ng cellphone *', krj: 'Numero it cellphone *' },
  'Municipality *': { fil: 'Munisipyo *', krj: 'Banwa *' },
  'Choose…': { fil: 'Pumili…', krj: 'Magpili…' },
  'Barangay *': { fil: 'Barangay *', krj: 'Barangay *' },
  'Password *': { fil: 'Password *', krj: 'Password *' },
  'New password': { fil: 'Bagong password', krj: 'Bag-o nga password' },
  'Give it to the person; they sign in with it in the app or here.': {
    fil: 'Ibigay ito sa tao; gagamitin niya ito sa pag-log in sa app o dito.',
    krj: 'Ihatag kadya sa tawo; gamiton na kadya sa pag-log in sa app ukon diya.',
  },
  'Leave empty to keep the current password.': {
    fil: 'Iwanang blangko para hindi mapalitan ang password.',
    krj: 'Pabay-i nga blangko para indi mailisan ang password.',
  },
  'At least 8 characters': { fil: 'Hindi bababa sa 8 character', krj: 'Indi magnubo sa 8 ka character' },
  'Delete account': { fil: 'Burahin ang account', krj: 'Panasa ang account' },
  'Create account': { fil: 'Gumawa ng account', krj: 'Maghimo it account' },
  'Save changes': { fil: 'I-save ang mga pagbabago', krj: 'I-save ang mga ginbag-o' },
  'Delete {name}?': { fil: 'Burahin si {name}?', krj: 'Panason si {name}?' },
  "They can no longer sign in to the app or the dashboard. Their {n} observation stay in the records and reports. This can't be undone.":
    {
      fil: 'Hindi na makakapag-log in sa app o sa dashboard. Mananatili sa mga rekord at report ang {n} obserbasyon. Hindi na ito maibabalik.',
      krj: 'Indi run makapag-log in sa app ukon sa dashboard. Magapabilin sa mga rekord kag report ang {n} ka obserbasyon. Indi run mabalik kadya.',
    },
  "They can no longer sign in to the app or the dashboard. Their {n} observations stay in the records and reports. This can't be undone.":
    {
      fil: 'Hindi na makakapag-log in sa app o sa dashboard. Mananatili sa mga rekord at report ang {n} obserbasyon. Hindi na ito maibabalik.',
      krj: 'Indi run makapag-log in sa app ukon sa dashboard. Magapabilin sa mga rekord kag report ang {n} ka obserbasyon. Indi run mabalik kadya.',
    },
  'Keep the account': { fil: 'Huwag burahin ang account', krj: 'Indi pagpanasa ang account' },
  'Yes, delete it': { fil: 'Oo, burahin', krj: 'Huo, panasa' },

  // ---------------------------------------------------------------- accounts table
  '(you)': { fil: '(ikaw)', krj: '(ikaw)' },
  'Joined {date} · {n} observation': { fil: 'Nagparehistro {date} · {n} obserbasyon', krj: 'Nagparehistro {date} · {n} ka obserbasyon' },
  'Joined {date} · {n} observations': { fil: 'Nagparehistro {date} · {n} obserbasyon', krj: 'Nagparehistro {date} · {n} ka obserbasyon' },
  'Email not verified': { fil: 'Hindi pa verified ang email', krj: 'Wara pa na-verify ang email' },
  'Edit {name}': { fil: 'I-edit si {name}', krj: 'I-edit si {name}' },
  'Delete {name}': { fil: 'Burahin si {name}', krj: 'Panasa si {name}' },
  'Name, email, phone, barangay…': { fil: 'Pangalan, email, numero, barangay…', krj: 'Ngaran, email, numero, barangay…' },
  'All roles': { fil: 'Lahat ng tungkulin', krj: 'Tanan nga role' },
  'Add account': { fil: 'Magdagdag ng account', krj: 'Magdugang it account' },
  Account: { fil: 'Account', krj: 'Account' },
  Area: { fil: 'Lugar', krj: 'Lugar' },
  'No accounts match': { fil: 'Walang tugmang account', krj: 'Wara it tugma nga account' },
  'validates observations in their coverage': {
    fil: 'nagva-validate ng mga obserbasyon sa sakop niya',
    krj: 'naga-validate it mga obserbasyon sa sakop nga lugar',
  },
  'sees every area, resolves escalations and manages this dashboard.': {
    fil: 'nakikita ang lahat ng lugar, inaasikaso ang mga ipinasang kaso at namamahala sa dashboard na ito.',
    krj: 'nakita ang tanan nga lugar, ginaasikaso ang mga ginpasa nga kaso kag nagadumala it dashboard nga kadya.',
  },
  'Delete this account?': { fil: 'Burahin ang account na ito?', krj: 'Panason ang account nga kadya?' },

  // ---------------------------------------------------------------- coverage grid
  Covered: { fil: 'May technician', krj: 'May technician' },
  'No technician': { fil: 'Walang technician', krj: 'Wara it technician' },
  '(agriculturist)': { fil: '(agriculturist)', krj: '(agriculturist)' },
  Farmers: { fil: 'Magsasaka', krj: 'Mangunguma' },
  'Obs.': { fil: 'Obs.', krj: 'Obs.' },
  "{n} municipality has no technician: {list}. Observations from there wait in no one's queue. Assign a technician under Accounts.": {
    fil: '{n} munisipyo ang walang technician: {list}. Ang mga obserbasyon mula roon ay hindi napupunta sa pila ng kahit sino. Magtalaga ng technician sa Mga account.',
    krj: '{n} ka banwa ang wara it technician: {list}. Ang mga obserbasyon halin rugto indi makadto sa pila it bisan sin-o. Magtoka it technician sa Mga account.',
  },
  "{n} municipalities have no technician: {list}. Observations from there wait in no one's queue. Assign a technician under Accounts.": {
    fil: '{n} munisipyo ang walang technician: {list}. Ang mga obserbasyon mula roon ay hindi napupunta sa pila ng kahit sino. Magtalaga ng technician sa Mga account.',
    krj: '{n} ka banwa ang wara it technician: {list}. Ang mga obserbasyon halin rugto indi makadto sa pila it bisan sin-o. Magtoka it technician sa Mga account.',
  },

  // ---------------------------------------------------------------- page
  'Changes apply right away, in the app and on the dashboard.': {
    fil: 'Agad na magkakabisa ang mga pagbabago, sa app at sa dashboard.',
    krj: 'Dayon nga ma-apply ang mga ginbag-o, sa app kag sa dashboard.',
  },
  'User management': { fil: 'Pamamahala ng user', krj: 'Pagdumala it user' },
  'Approve new accounts; add, edit or delete accounts (details, role, profile picture, password); and set the municipality and barangays a technician covers. Coverage decides whose queue an observation lands in.':
    {
      fil: 'Aprubahan ang mga bagong account; magdagdag, mag-edit o magbura ng account (detalye, tungkulin, litrato sa profile, password); at itakda ang munisipyo at mga barangay na sakop ng technician. Ang sakop ang nagpapasya kung kaninong pila mapupunta ang obserbasyon.',
      krj: 'Aprubahan ang mga bag-o nga account; magdugang, mag-edit ukon magpanas it account (detalye, role, litrato sa profile, password); kag ibutang ang banwa kag mga barangay nga sakop it technician. Ang sakop ang nagadesisyon kon kay sin-o nga pila makadto ang obserbasyon.',
    },
  'Accounts ({n})': { fil: 'Mga account ({n})', krj: 'Mga account ({n})' },
  'Coverage by municipality': { fil: 'Sakop ayon sa munisipyo', krj: 'Sakop suno sa banwa' },
};
