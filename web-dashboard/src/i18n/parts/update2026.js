// Translations for the 2026-12 update (review queues, reviewer notes,
// recommendations, land type corrections, spread, saved data, paging,
// confirmations, provisional thresholds, guide sections).
// Machine-assisted; NOT reviewed by a language expert (see docs/GLOSSARY.md).
// Key = the English text used in the code. Keep {placeholders} unchanged.
export default {
  // ---- queues and statuses (same statuses, clearer names)
  'Not Validated': { fil: 'Hindi pa Na-validate', krj: 'Wara pa Na-validate' },
  'To Be Validated': { fil: 'Ive-validate pa', krj: 'Pagavalidaron pa' },
  'Not Validated queue': { fil: 'Pila ng Hindi pa Na-validate', krj: 'Pila it Wara pa Na-validate' },
  'To Be Validated, and Not Validated from areas without a technician': {
    fil: 'Ive-validate pa, at Hindi pa Na-validate mula sa lugar na walang technician',
    krj: 'Pagavalidaron pa, kag Wara pa Na-validate halin sa lugar nga wara it technician',
  },
  'Both queues': { fil: 'Parehong pila', krj: 'Duha ka pila' },
  'Escalated to To Be Validated': { fil: 'Ipinasa sa Ive-validate pa', krj: 'Ginpasa sa Pagavalidaron pa' },
  'Land type corrected': { fil: 'Itinama ang uri ng lupa', krj: 'Gintadlong ang klase it duta' },

  // ---- sign-out, saved data, paging, confirmation
  'Sign out?': { fil: 'Mag-sign out?', krj: 'Mag-sign out?' },
  'You will need your email and password to sign in again. Anything you have not saved on this page, such as a review you are writing, will be lost.': {
    fil: 'Kakailanganin mo ang iyong email at password para mag-sign in ulit. Mawawala ang anumang hindi mo pa nai-save sa pahinang ito, tulad ng pagsusuring isinusulat mo.',
    krj: 'Kinahanglanon mo ang imo nga email kag password para mag-sign in liwan. Madula ang bisan ano nga wara mo pa ma-save sa pahina nga dya, pareho it pag-usisa nga ginasulat mo.',
  },
  'Showing data saved on {time} because the server could not be reached. It updates when the connection is back.': {
    fil: 'Ipinapakita ang datos na na-save noong {time} dahil hindi maabot ang server. Mag-a-update ito kapag bumalik ang koneksyon.',
    krj: 'Ginapakita ang datos nga na-save kang {time} tungod indi maabot ang server. Mag-update dya kon magbalik ang koneksyon.',
  },
  'Please wait…': { fil: 'Sandali lang…', krj: 'Hulat anay…' },
  Confirm: { fil: 'Kumpirmahin', krj: 'Kumpirmaha' },
  'Yes, continue': { fil: 'Oo, ituloy', krj: 'Huo, padayuna' },
  '{n} shown': { fil: '{n} ang ipinapakita', krj: '{n} ang ginapakita' },
  '{first}–{last} of {total}': { fil: '{first}–{last} sa {total}', krj: '{first}–{last} sa {total}' },
  Previous: { fil: 'Nakaraan', krj: 'Nauna' },
  Next: { fil: 'Susunod', krj: 'Masunod' },
  'Validate this observation?': { fil: 'I-validate ang obserbasyong ito?', krj: 'I-validate ang obserbasyon nga dya?' },
  'The level becomes the official record and the farmer is notified.': {
    fil: 'Magiging opisyal na rekord ang antas at aabisuhan ang magsasaka.',
    krj: 'Mangin opisyal nga rekord ang lebel kag pahibaluon ang mangunguma.',
  },
  'Return it to the farmer?': { fil: 'Ibalik sa magsasaka?', krj: 'Ibalik sa mangunguma?' },
  'The farmer is asked to take a new photo. This observation stays in the records as returned.': {
    fil: 'Hihilingin sa magsasaka na kumuha ng bagong litrato. Mananatili ang obserbasyong ito sa rekord bilang ibinalik.',
    krj: 'Pangayuon sa mangunguma nga magkuha it bag-o nga litrato. Magapabilin ang obserbasyon nga dya sa rekord bilang ginbalik.',
  },
  'Escalate to an agriculturist?': { fil: 'Ipasa sa agriculturist?', krj: 'Ipasa sa agriculturist?' },
  'It leaves your queue and goes to the To Be Validated queue.': {
    fil: 'Aalis ito sa iyong pila at mapupunta sa pila ng Ive-validate pa.',
    krj: 'Mahalin dya sa imo nga pila kag makadto sa pila it Pagavalidaron pa.',
  },
  'Reject this account?': { fil: 'Tanggihan ang account na ito?', krj: 'Balibaran ang account nga dya?' },
  'Delete this option?': { fil: 'Burahin ang opsyong ito?', krj: 'Panasan ang opsyon nga dya?' },
  'Remove these thresholds?': { fil: 'Alisin ang mga threshold na ito?', krj: 'Kuhaon ang mga threshold nga dya?' },

  // ---- review form
  'Reviewer note': { fil: 'Tala ng nagsuri', krj: 'Tala it nag-usisa' },
  'Reviewer note *': { fil: 'Tala ng nagsuri *', krj: 'Tala it nag-usisa *' },
  'What you checked and why you chose this level. Kept in the review history for technicians and agriculturists; it is not the guidance the farmer reads.': {
    fil: 'Ano ang sinuri mo at bakit ito ang antas na pinili mo. Itinatago sa kasaysayan ng pagsusuri para sa technician at agriculturist; hindi ito ang payong binabasa ng magsasaka.',
    krj: 'Ano ang gin-usisa mo kag ham-an dya ang lebel nga ginpili mo. Ginatago sa kasaysayan it pag-usisa para sa technician kag agriculturist; indi dya ang tugon nga ginabasa it mangunguma.',
  },
  'e.g. Counted 6 rice bugs on two panicles; grains not yet damaged': {
    fil: 'hal. Nabilang ang 6 na atangya sa dalawang uhay; hindi pa nasisira ang butil',
    krj: 'pananglitan: Naisip ang 6 ka tiyangaw sa duha ka uhay; wara pa naguba ang uyas',
  },
  'Recommend treatment options': { fil: 'Magrekomenda ng lunas', krj: 'Magrekomenda it bulong' },
  'Picked from the approved treatment library. The farmer sees them as recommendations; what they actually apply is recorded separately.': {
    fil: 'Pinili mula sa aprubadong listahan ng lunas. Makikita ito ng magsasaka bilang rekomendasyon; hiwalay na itinatala ang talagang ginawa nila.',
    krj: 'Ginpili halin sa aprobado nga listahan it bulong. Makita dya it mangunguma bilang rekomendasyon; lain nga ginatala ang matuod nga ginhimo nanda.',
  },
  'No approved options for this pest yet.': {
    fil: 'Wala pang aprubadong opsyon para sa pesteng ito.',
    krj: 'Wara pa it aprobado nga opsyon para sa peste nga dya.',
  },
  'Write a clear reason the farmer can act on.': {
    fil: 'Sumulat ng malinaw na dahilan na magagawa ng magsasaka.',
    krj: 'Magsulat it malinaw nga rason nga mahimo it mangunguma.',
  },
  'Explain the escalation in a sentence the agriculturist can use.': {
    fil: 'Ipaliwanag ang pagpasa sa isang pangungusap na magagamit ng agriculturist.',
    krj: 'Ipaathag ang pagpasa sa isa ka pangungusap nga magamit it agriculturist.',
  },
  'Add a reviewer note: what you checked and why you chose this level.': {
    fil: 'Magdagdag ng tala ng nagsuri: ano ang sinuri mo at bakit ito ang antas na pinili mo.',
    krj: 'Magdugang it tala it nag-usisa: ano ang gin-usisa mo kag ham-an dya ang lebel nga ginpili mo.',
  },
  'The reviewer note must be your own note, not a copy of the diagnosis or guidance.': {
    fil: 'Dapat sariling tala mo ang tala ng nagsuri, hindi kopya ng diagnosis o payo.',
    krj: 'Dapat imo gid nga tala ang tala it nag-usisa, indi kopya it diagnosis ukon tugon.',
  },
  'Provisional thresholds: not yet confirmed by an agriculturist. Rely on what you see in the field.': {
    fil: 'Pansamantalang threshold: hindi pa kinukumpirma ng agriculturist. Umasa sa nakikita mo sa bukid.',
    krj: 'Temporaryo nga threshold: wara pa ginkumpirma it agriculturist. Magsalig sa nakita mo sa uma.',
  },
  'This photo may not show a rice plant or field. Check it before validating, and return it if it is not a photo of the field.': {
    fil: 'Maaaring hindi palay o bukid ang nasa litratong ito. Suriin bago i-validate, at ibalik kung hindi ito litrato ng bukid.',
    krj: 'Pwede indi humay ukon uma ang sa litrato nga dya. Usisaa antes i-validate, kag ibalik kon indi dya litrato it uma.',
  },
  'This photo may not show a rice plant or field. A technician will check it.': {
    fil: 'Maaaring hindi palay o bukid ang nasa litratong ito. Susuriin ito ng technician.',
    krj: 'Pwede indi humay ukon uma ang sa litrato nga dya. Usisaon dya it technician.',
  },
  'Possibly unrelated photo': { fil: 'Posibleng hindi kaugnay na litrato', krj: 'Posible nga indi angot nga litrato' },
  'The model found insects, but its labels for this pest have not been verified yet. A technician will identify them.': {
    fil: 'May nakitang insekto ang model, pero hindi pa napapatunayan ang label nito para sa pesteng ito. Tutukuyin ito ng technician.',
    krj: 'May nakita nga insekto ang model, pero wara pa napamatud-an ang label nana para sa peste nga dya. Tukuyon dya it technician.',
  },

  // ---- record panel
  'Recommended by the reviewer': { fil: 'Inirekomenda ng nagsuri', krj: 'Ginrekomenda it nag-usisa' },
  'The reviewer did not recommend specific options.': {
    fil: 'Hindi nagrekomenda ng tiyak na opsyon ang nagsuri.',
    krj: 'Wara nagrekomenda it espesipiko nga opsyon ang nag-usisa.',
  },
  'No longer approved': { fil: 'Hindi na aprubado', krj: 'Indi run aprobado' },
  'Recommended by {name}': { fil: 'Inirekomenda ni {name}', krj: 'Ginrekomenda ni {name}' },
  Correct: { fil: 'Itama', krj: 'Tadlunga' },
  'Choose the land type': { fil: 'Piliin ang uri ng lupa', krj: 'Pilia ang klase it duta' },
  'Why (optional, kept in the history)': {
    fil: 'Bakit (opsyonal, itatago sa kasaysayan)',
    krj: 'Ham-an (opsyonal, itago sa kasaysayan)',
  },
  'Corrected by {name}': { fil: 'Itinama ni {name}', krj: 'Gintadlong ni {name}' },
  'Recommendations, not treatments applied': {
    fil: 'Mga rekomendasyon, hindi lunas na ginawa',
    krj: 'Mga rekomendasyon, indi bulong nga ginhimo',
  },
  'Treatments applied by the farmer': { fil: 'Lunas na ginawa ng magsasaka', krj: 'Bulong nga ginhimo it mangunguma' },

  // ---- criteria
  Provisional: { fil: 'Pansamantala', krj: 'Temporaryo' },
  Confirmed: { fil: 'Kumpirmado', krj: 'Kumpirmado' },
  'Thresholds marked provisional again.': {
    fil: 'Ibinalik sa pansamantala ang mga threshold.',
    krj: 'Ginbalik sa temporaryo ang mga threshold.',
  },
  'Mark provisional': { fil: 'Gawing pansamantala', krj: 'Himuon nga temporaryo' },
  'Confirm with a source': { fil: 'Kumpirmahin gamit ang sanggunian', krj: 'Kumpirmaha gamit ang ginhalinan' },
  'Source you checked these numbers against *': {
    fil: 'Sanggunian na pinagbatayan mo ng mga numerong ito *',
    krj: 'Ginhalinan nga ginbasehan mo it mga numero nga dya *',
  },
  'e.g. the title and year of the guide or memo your office uses.': {
    fil: 'hal. ang pamagat at taon ng gabay o memo na ginagamit ng inyong opisina.',
    krj: 'pananglitan: ang titulo kag tuig it giya ukon memo nga ginagamit it inyo nga opisina.',
  },
  'Thresholds confirmed.': { fil: 'Nakumpirma ang mga threshold.', krj: 'Nakumpirma ang mga threshold.' },
  'Confirmed by {name} · {date} · source: {source}': {
    fil: 'Kinumpirma ni {name} · {date} · sanggunian: {source}',
    krj: 'Ginkumpirma ni {name} · {date} · ginhalinan: {source}',
  },
  'Provisional thresholds in use': { fil: 'Pansamantalang threshold ang ginagamit', krj: 'Temporaryo nga threshold ang ginagamit' },
  'for {pests}. They have not been confirmed against an agronomic reference by an agriculturist, so suggested levels are provisional.': {
    fil: 'para sa {pests}. Hindi pa ito kinukumpirma ng agriculturist batay sa sanggunian sa agrikultura, kaya pansamantala ang mungkahing antas.',
    krj: 'para sa {pests}. Wara pa dya ginkumpirma it agriculturist base sa ginhalinan sa agrikultura, gani temporaryo ang ginsugid nga lebel.',
  },
  'Check each row against the reference your office uses, then confirm it with that source.': {
    fil: 'Suriin ang bawat hanay batay sa sanggunian ng inyong opisina, saka kumpirmahin gamit ang sanggunian na iyon.',
    krj: 'Usisaa ang kada linya base sa ginhalinan it inyo nga opisina, dayon kumpirmaha gamit ang ginhalinan nga ato.',
  },
  'An agriculturist still needs to confirm them. Rely on what you see in the field when confirming a level.': {
    fil: 'Kailangan pa itong kumpirmahin ng agriculturist. Umasa sa nakikita mo sa bukid kapag nagkukumpirma ng antas.',
    krj: 'Kinahanglan pa dya kumpirmahon it agriculturist. Magsalig sa nakita mo sa uma kon nagakumpirma it lebel.',
  },

  // ---- guide
  Model: { fil: 'Model', krj: 'Model' },
  People: { fil: 'Tao', krj: 'Tawo' },
  'Detected by the photo model': { fil: 'Natutukoy ng photo model', krj: 'Natukoy it photo model' },
  'Checked by people in the field': { fil: 'Sinusuri ng tao sa bukid', krj: 'Ginausisa it tawo sa uma' },
  'The model does not detect these. Reviewers tick them when they see them in the photo or the field.': {
    fil: 'Hindi ito natutukoy ng model. Tsine-tsekan ito ng nagsuri kapag nakita sa litrato o sa bukid.',
    krj: 'Indi dya natukoy it model. Gina-tsek dya it nag-usisa kon nakita sa litrato ukon sa uma.',
  },
  'Damage linked to {pest}': { fil: 'Pinsalang kaugnay ng {pest}', krj: 'Danyos nga angot sa {pest}' },
  Glossary: { fil: 'Talahuluganan', krj: 'Glosaryo' },

  // ---- map / spread
  'From-To dates': { fil: 'Petsa Mula-Hanggang', krj: 'Petsa Halin-Tubtob' },
  'Observation period {period}': { fil: 'Panahon ng obserbasyon {period}', krj: 'Panahon it obserbasyon {period}' },
  'Where validated cases cluster in two consecutive periods': {
    fil: 'Kung saan nagkukumpol ang mga na-validate na kaso sa dalawang magkasunod na panahon',
    krj: 'Kon diin nagatipon ang mga na-validate nga kaso sa duha ka sunod-sunod nga panahon',
  },
  'Based on validated cases with a reliable location only. It shows observed movement, not a forecast.': {
    fil: 'Batay lamang sa mga na-validate na kaso na may maaasahang lokasyon. Ipinapakita nito ang naobserbahang paggalaw, hindi hula.',
    krj: 'Base lang sa mga na-validate nga kaso nga may masaligan nga lokasyon. Ginapakita dya ang naobserbahan nga paghulag, indi hula.',
  },
  'Set both the From and To dates above to compare the two halves of that range.': {
    fil: 'Itakda ang petsang Mula at Hanggang sa itaas para maihambing ang dalawang hati ng saklaw na iyon.',
    krj: 'Ibutang ang petsa nga Halin kag Tubtob sa ibabaw para maikumparar ang duha ka bahin it sakop nga ato.',
  },
  '{used} validated cases used; {excluded} left out because their location is missing, outside Antique or too inaccurate. At least {n} cases are needed in each period.': {
    fil: '{used} na-validate na kaso ang ginamit; {excluded} ang hindi isinama dahil walang lokasyon, nasa labas ng Antique o hindi tumpak. Kailangan ng hindi bababa sa {n} kaso bawat panahon.',
    krj: '{used} ka na-validate nga kaso ang ginamit; {excluded} ang wara ginlakip tungod wara it lokasyon, sa guwa it Antique ukon indi eksakto. Kinahanglan indi magnubo sa {n} ka kaso kada panahon.',
  },
  '{n} case(s) left out: unreliable location.': {
    fil: '{n} kaso ang hindi isinama: hindi maaasahan ang lokasyon.',
    krj: '{n} ka kaso ang wara ginlakip: indi masaligan ang lokasyon.',
  },

  // ---- records
  'Photo check': { fil: 'Pagsuri ng litrato', krj: 'Pag-usisa it litrato' },
  'All photos': { fil: 'Lahat ng litrato', krj: 'Tanan nga litrato' },
  Relevant: { fil: 'Kaugnay', krj: 'Angot' },
  'Sort by': { fil: 'Ayusin ayon sa', krj: 'Hanayon base sa' },
  'Newest first': { fil: 'Pinakabago muna', krj: 'Pinakabag-o anay' },
  'Highest level first': { fil: 'Pinakamataas na antas muna', krj: 'Pinakamataas nga lebel anay' },
  'Municipality (A-Z)': { fil: 'Munisipyo (A-Z)', krj: 'Banwa (A-Z)' },
  'Pest (A-Z)': { fil: 'Peste (A-Z)', krj: 'Peste (A-Z)' },
  'Downloads every observation that matches these filters, not only this page.': {
    fil: 'Dina-download ang lahat ng obserbasyong tugma sa mga filter na ito, hindi lang ang pahinang ito.',
    krj: 'Gina-download ang tanan nga obserbasyon nga tugma sa mga filter nga dya, indi lang ang pahina nga dya.',
  },
  'Export these records (CSV)': { fil: 'I-export ang mga rekord na ito (CSV)', krj: 'I-export ang mga rekord nga dya (CSV)' },
  'Name, email, barangay…': { fil: 'Pangalan, email, barangay…', krj: 'Ngaran, email, barangay…' },

  // ---- treatments and outcomes
  Worsened: { fil: 'Lumala', krj: 'Naglala' },
  'Not comparable': { fil: 'Hindi maihahambing', krj: 'Indi maikumparar' },
  'no pests detected, not reviewed': {
    fil: 'walang nakitang peste, hindi pa nasuri',
    krj: 'wara it nakita nga peste, wara pa nausisa',
  },
  'follow-up not reviewed yet': { fil: 'hindi pa nasusuri ang follow-up', krj: 'wara pa nausisa ang follow-up' },
  '{improved} improved · {same} no change · {worse} worsened': {
    fil: '{improved} bumuti · {same} walang pagbabago · {worse} lumala',
    krj: '{improved} nagmayad · {same} wara it pagbag-o · {worse} naglala',
  },
  'Applications with the same name are grouped. Improved / no change / worsened counts only treatments whose follow-up was reviewed and shows the same pest. A follow-up photo with no pests detected is not counted as improved until a technician reviews it.': {
    fil: 'Pinagsasama ang mga lunas na may parehong pangalan. Ang bumuti / walang pagbabago / lumala ay binibilang lamang kapag nasuri ang follow-up at parehong peste ang nakita. Hindi itinuturing na bumuti ang follow-up na litratong walang nakitang peste hangga\'t hindi ito nasusuri ng technician.',
    krj: 'Ginatipon ang mga bulong nga pareho ang ngaran. Ang nagmayad / wara it pagbag-o / naglala ginaisip lang kon nausisa ang follow-up kag pareho nga peste ang nakita. Indi ginaisip nga nagmayad ang follow-up nga litrato nga wara it nakita nga peste hasta indi pa dya nausisa it technician.',
  },
  'Improved / no change / worsened': {
    fil: 'Bumuti / walang pagbabago / lumala',
    krj: 'Nagmayad / wara it pagbag-o / naglala',
  },
  '{n} still pending': { fil: '{n} ang naghihintay pa', krj: '{n} ang nagahulat pa' },
  improved: { fil: 'bumuti', krj: 'nagmayad' },
  'no change': { fil: 'walang pagbabago', krj: 'wara it pagbag-o' },
  worsened: { fil: 'lumala', krj: 'naglala' },
  'not comparable': { fil: 'hindi maihahambing', krj: 'indi maikumparar' },
  'confirmed level': { fil: 'kinumpirmang antas', krj: 'ginkumpirma nga lebel' },
  'count (same level)': { fil: 'bilang (parehong antas)', krj: 'kadamuon (pareho nga lebel)' },
  'level missing': { fil: 'walang antas', krj: 'wara it lebel' },
  'no follow-up yet': { fil: 'wala pang follow-up', krj: 'wara pa it follow-up' },
  'follow-up photo not reviewed (no pests detected)': {
    fil: 'hindi pa nasusuri ang follow-up na litrato (walang nakitang peste)',
    krj: 'wara pa nausisa ang follow-up nga litrato (wara it nakita nga peste)',
  },
  'different pest confirmed on the follow-up': {
    fil: 'ibang peste ang nakumpirma sa follow-up',
    krj: 'lain nga peste ang nakumpirma sa follow-up',
  },

  // ---- pest names and option types (shown through t())
  'Brown Planthopper': { fil: 'Brown planthopper (kayumangging hanip)', krj: 'Brown planthopper (kayumanggi nga hanip)' },
  'Green Leafhopper': { fil: 'Green leafhopper (berdeng leafhopper)', krj: 'Green leafhopper (berde nga leafhopper)' },
  'Rice Bug': { fil: 'Atangya (rice bug)', krj: 'Tiyangaw (rice bug)' },
  'Rice Stem Borer': { fil: 'Aksip (stem borer)', krj: 'Uod sa tangkay (stem borer)' },

  // ---- server messages (exact text the API sends)
  'The server had a problem. Please try again in a moment.': {
    fil: 'Nagkaproblema ang server. Pakisubukan ulit mamaya.',
    krj: 'Nagkaproblema ang server. Palihog tilawi liwan dugay-dugay.',
  },
  'The request failed. Please try again.': {
    fil: 'Hindi natuloy ang hiling. Pakisubukan ulit.',
    krj: 'Wara natuloy ang pangayo. Palihog tilawi liwan.',
  },
  "Can't reach the server. Check your connection and that the API is running.": {
    fil: 'Hindi maabot ang server. Suriin ang koneksyon at kung tumatakbo ang API.',
    krj: 'Indi maabot ang server. Usisaa ang koneksyon kag kon nagadalagan ang API.',
  },
  'This option was recommended on observations. Move it back to draft instead of deleting it.': {
    fil: 'Inirekomenda na ang opsyong ito sa mga obserbasyon. Ibalik ito sa draft sa halip na burahin.',
    krj: 'Ginrekomenda run ang opsyon nga dya sa mga obserbasyon. Ibalik dya sa draft imbes nga panasan.',
  },
  'Recommend only approved library options for the confirmed pest.': {
    fil: 'Magrekomenda lamang ng aprubadong opsyon para sa nakumpirmang peste.',
    krj: 'Magrekomenda lang it aprobado nga opsyon para sa nakumpirma nga peste.',
  },
  'Treatment options can only be recommended for pest reports.': {
    fil: 'Para lamang sa ulat ng peste ang pagrekomenda ng lunas.',
    krj: 'Para lang sa report it peste ang pagrekomenda it bulong.',
  },
  'Choose a date range of 2 to 366 days.': {
    fil: 'Pumili ng saklaw na 2 hanggang 366 na araw.',
    krj: 'Magpili it sakop nga 2 tubtob 366 ka adlaw.',
  },
  "The land type can't be changed after review. Ask your technician.": {
    fil: 'Hindi na mababago ang uri ng lupa pagkatapos ng pagsusuri. Magtanong sa iyong technician.',
    krj: 'Indi run mabag-o ang klase it duta pagkatapos it pag-usisa. Mamangkot sa imo nga technician.',
  },
  'Thresholds not found.': { fil: 'Hindi makita ang mga threshold.', krj: 'Indi makita ang mga threshold.' },
  'This needs a database update first.': {
    fil: 'Kailangan munang i-update ang database.',
    krj: 'Kinahanglan anay i-update ang database.',
  },
  'Recommendations need a database update first.': {
    fil: 'Kailangan munang i-update ang database para sa mga rekomendasyon.',
    krj: 'Kinahanglan anay i-update ang database para sa mga rekomendasyon.',
  },
};
