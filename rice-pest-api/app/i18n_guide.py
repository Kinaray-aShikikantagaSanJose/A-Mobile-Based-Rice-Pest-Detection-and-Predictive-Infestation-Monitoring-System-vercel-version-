"""Filipino (fil) and Kinaray-a (krj) text for the pest guide, the damage
indicators and the glossary, keyed by the English text (like the apps'
string tables). English stays the source of truth: app/guide.py.

STATUS: machine-assisted translations, NOT reviewed by a language expert or
an agriculturist. The guide shows this status to users (translation_status).
Pest and symptom names keep the English term in brackets where the local
name is not widely known, so a technician can always match them.
"""

GUIDE_LABELS = {
    # ---- titles and notes
    "What to look for": {"fil": "Ano ang dapat hanapin", "krj": "Ano ang dapat usisaon"},
    "Detected by the photo model": {"fil": "Natutukoy ng photo model", "krj": "Natukoy it photo model"},
    "Checked by people in the field": {"fil": "Sinusuri ng tao sa bukid", "krj": "Ginausisa it tawo sa uma"},
    "The model looks for the four insects only. It does not detect symptoms such as deadhearts, "
    "whiteheads or hopperburn; your technician checks those in the field and in the photo.": {
        "fil": "Apat na insekto lamang ang hinahanap ng model. Hindi nito natutukoy ang mga sintomas tulad ng "
               "deadheart, whitehead o hopperburn; sinusuri iyon ng iyong technician sa bukid at sa litrato.",
        "krj": "Apat lang ka insekto ang ginapangita it model. Indi nana matukoy ang mga sintomas pareho it "
               "deadheart, whitehead ukon hopperburn; ginausisa dya it imo nga technician sa uma kag sa litrato.",
    },
    "A model result is a suggestion. A technician confirms every pest, count and level.": {
        "fil": "Mungkahi lamang ang resulta ng model. Kinukumpirma ng technician ang bawat peste, bilang at antas.",
        "krj": "Suhestiyon lang ang resulta it model. Ginakumpirma it technician ang kada peste, kadamuon kag lebel.",
    },
    "Translations are machine-assisted and have not been reviewed by an expert.": {
        "fil": "Ang mga salin ay tinulungan ng makina at hindi pa nasusuri ng eksperto.",
        "krj": "Ang mga lubad ginbuligan it makina kag wara pa nausisa it eksperto.",
    },
    # ---- pest signs
    "Small brown insects, 3-4 mm, packed at the base of the plants near the water.": {
        "fil": "Maliliit na kayumangging insekto, 3-4 mm, nagkukumpol sa puno ng palay malapit sa tubig.",
        "krj": "Gagmay nga kayumanggi nga insekto, 3-4 mm, nagatipon sa puno it humay malapit sa tubig.",
    },
    "Long-winged and short-winged adults; young ones (nymphs) are creamy white to light brown.": {
        "fil": "May mahaba at maikling pakpak ang mga adulto; ang mga bata (nymph) ay puting-krema hanggang mapusyaw na kayumanggi.",
        "krj": "May malaba kag malip-ot nga pakpak ang mga dalagko; ang mga bata (nymph) maputi-krema tubtob maluspad nga kayumanggi.",
    },
    "They move sideways or drop into the water when the plant is tapped.": {
        "fil": "Gumagalaw sila patagilid o nahuhulog sa tubig kapag tinapik ang halaman.",
        "krj": "Nagahulag sanda patagilid ukon nagahulog sa tubig kon tapikon ang tanum.",
    },
    "Bright green, wedge-shaped insects, 3-5 mm, on the upper leaves.": {
        "fil": "Matingkad na berdeng insekto na hugis-kalang, 3-5 mm, nasa itaas na dahon.",
        "krj": "Masilaw nga berde nga insekto nga hugis-kalang, 3-5 mm, sa ibabaw nga dahon.",
    },
    "Many have black spots or a black band on the wing tips.": {
        "fil": "Marami ang may itim na batik o itim na guhit sa dulo ng pakpak.",
        "krj": "Madamo ang may itom nga mansa ukon itom nga guhit sa dulo it pakpak.",
    },
    "They jump or fly off quickly when disturbed.": {
        "fil": "Mabilis silang tumatalon o lumilipad kapag nagambala.",
        "krj": "Madasig sanda nga nagalukso ukon nagalupad kon gin-istorbo.",
    },
    "Slender green-to-brown bugs, 14-17 mm, with long legs and long antennae.": {
        "fil": "Payat na berde hanggang kayumangging insekto, 14-17 mm, mahaba ang paa at antena.",
        "krj": "Manipis nga berde tubtob kayumanggi nga insekto, 14-17 mm, malaba ang tiil kag antena.",
    },
    "Usually on the panicles, sucking the developing grains.": {
        "fil": "Karaniwang nasa uhay, sinisipsip ang mga butil na nabubuo pa.",
        "krj": "Kasarangan sa uhay, ginasup-sup ang mga uyas nga ginaporma pa.",
    },
    "A strong, unpleasant smell in the field.": {
        "fil": "Matapang at hindi kanais-nais na amoy sa bukid.",
        "krj": "Mabaskog kag malain nga baho sa uma.",
    },
    "Moths: pale yellow to white; the female yellow stem borer has a black dot on each forewing.": {
        "fil": "Gamu-gamo: maputlang dilaw hanggang puti; ang babaeng yellow stem borer ay may itim na tuldok sa bawat pakpak sa unahan.",
        "krj": "Alibangbang: maluspad nga dulaw tubtob puti; ang babaye nga yellow stem borer may itom nga tuldok sa kada pakpak sa unahan.",
    },
    "Egg masses on the leaf tips, covered with light brown hairs.": {
        "fil": "Kumpol ng itlog sa dulo ng dahon, natatakpan ng mapusyaw na kayumangging buhok.",
        "krj": "Tipon it itlog sa dulo it dahon, natabunan it maluspad nga kayumanggi nga balahibo.",
    },
    "Larvae (caterpillars) feed inside the stem, so they are rarely seen.": {
        "fil": "Ang mga uod ay kumakain sa loob ng tangkay, kaya bihira silang makita.",
        "krj": "Ang mga ulod nagakaon sa sulod it tangkay, gani indi sanda kasarangan makita.",
    },
    # ---- stage notes
    "Can appear at any stage; numbers build up from tillering, and damage is worst from booting to ripening.": {
        "fil": "Maaaring lumitaw sa anumang yugto; dumarami mula sa pagsusuwi, at pinakamalala ang pinsala mula pagbubuntis hanggang paghinog.",
        "krj": "Pwede maglitaw sa bisan ano nga yugto; nagadamo halin sa pagsuwi, kag pinakamalala ang danyos halin pagbusong tubtob paghinog.",
    },
    "Most important on young plants (seedling to tillering), when they spread tungro.": {
        "fil": "Pinakamahalaga sa batang halaman (punla hanggang pagsusuwi), kapag ikinakalat nila ang tungro.",
        "krj": "Pinakaimportante sa bata nga tanum (punla tubtob pagsuwi), kon ginapalapta nanda ang tungro.",
    },
    "From flowering to the milk and dough stages, when the grains are soft.": {
        "fil": "Mula pamumulaklak hanggang milk at dough stage, kapag malambot pa ang butil.",
        "krj": "Halin pagbulak tubtob milk kag dough stage, kon malumo pa ang uyas.",
    },
    "Deadhearts during the vegetative stage, whiteheads after the panicle forms.": {
        "fil": "Deadheart sa vegetative na yugto, whitehead pagkatapos mabuo ang uhay.",
        "krj": "Deadheart sa vegetative nga yugto, whitehead pagkatapos maporma ang uhay.",
    },
    # ---- symptom names
    "Hopperburn": {"fil": "Hopperburn (pagkasunog dahil sa hanip)", "krj": "Hopperburn (pagkasunog tungod sa hanip)"},
    "Honeydew or sooty mold": {"fil": "Honeydew o itim na amag", "krj": "Honeydew ukon itom nga agup-op"},
    "Wilting or lodging": {"fil": "Pagkalanta o pagkahiga ng palay", "krj": "Pagkalaya ukon pagkahiga it humay"},
    "Yellow-orange leaves (possible tungro)": {"fil": "Dilaw-kahel na dahon (posibleng tungro)", "krj": "Dulaw-kahel nga dahon (posible nga tungro)"},
    "Stunted plants": {"fil": "Bansot na halaman", "krj": "Bansot nga tanum"},
    "Reduced tillering": {"fil": "Kakaunting suwi", "krj": "Diutay nga suwi"},
    "Empty or unfilled grains": {"fil": "Ipa o hindi napunong butil", "krj": "Upa ukon wara napuno nga uyas"},
    "Brown spots on grains": {"fil": "Kayumangging batik sa butil", "krj": "Kayumanggi nga mansa sa uyas"},
    "Rice bug odor": {"fil": "Amoy ng atangya", "krj": "Baho it tiyangaw"},
    "Deadhearts": {"fil": "Deadheart (patay na usbong)", "krj": "Deadheart (patay nga ugbos)"},
    "Whiteheads": {"fil": "Whitehead (puting uhay na walang laman)", "krj": "Whitehead (puti nga uhay nga wara sulod)"},
    "Bore holes or frass": {"fil": "Butas o dumi ng uod sa tangkay", "krj": "Buho ukon tai it ulod sa tangkay"},
    # ---- symptom signs
    "Round patches of plants that turn yellow, then brown and dry, as if burned. "
    "The patches grow outward and plants in the middle collapse.": {
        "fil": "Pabilog na bahagi ng palay na naninilaw, saka nagiging kayumanggi at tuyo na parang nasunog. "
               "Lumalaki ang bahagi at bumabagsak ang palay sa gitna.",
        "krj": "Malingin nga parte it humay nga nagadulaw, dayon nagakayumanggi kag nagauga pareho it nasunog. "
               "Nagadaku ang parte kag nagahiga ang humay sa tunga.",
    },
    "Sticky, shiny honeydew on the lower stems; later a black, powdery mold grows on it.": {
        "fil": "Malagkit at makintab na honeydew sa ibabang tangkay; kalaunan ay tinutubuan ng itim at pulbos na amag.",
        "krj": "Malagkit kag masinaw nga honeydew sa idalom nga tangkay; dugay-dugay ginatubuan it itom kag pulbos nga agup-op.",
    },
    "Plants droop and fall over, starting from the base where the planthoppers feed.": {
        "fil": "Lumalaylay at natutumba ang palay, simula sa puno kung saan kumakain ang hanip.",
        "krj": "Nagalaylay kag nagatumba ang humay, halin sa puno kon diin nagakaon ang hanip.",
    },
    "Leaves turn yellow to orange starting from the tip; young leaves may look mottled. "
    "A sign of tungro virus, which green leafhoppers spread.": {
        "fil": "Naninilaw hanggang kumakahel ang dahon mula sa dulo; maaaring batik-batik ang batang dahon. "
               "Senyales ng tungro virus na ikinakalat ng green leafhopper.",
        "krj": "Nagadulaw tubtob nagakahel ang dahon halin sa dulo; pwede mansa-mansa ang bata nga dahon. "
               "Senyales it tungro virus nga ginapalapta it green leafhopper.",
    },
    "Plants clearly shorter than their neighbours, often in patches.": {
        "fil": "Halatang mas maikli ang halaman kaysa katabi, kadalasan ay pakumpol.",
        "krj": "Halata nga mas mubo ang tanum sangsa kataid, kasarangan patipon-tipon.",
    },
    "Hills with fewer tillers (shoots) than healthy hills nearby.": {
        "fil": "Mga puno na mas kaunti ang suwi kaysa malulusog na puno sa tabi.",
        "krj": "Mga puno nga mas diutay ang suwi sangsa mapagros nga puno sa kataid.",
    },
    "Grains that stay light, empty or only partly filled; panicles stay upright.": {
        "fil": "Butil na magaan, walang laman o kulang ang laman; nananatiling nakatayo ang uhay.",
        "krj": "Uyas nga magaan, wara sulod ukon kulang ang sulod; nagapabilin nga nakatindog ang uhay.",
    },
    "Small brown or black spots on the hulls where the bugs fed (pecky rice).": {
        "fil": "Maliliit na kayumanggi o itim na batik sa balat ng butil kung saan kumain ang insekto (pecky rice).",
        "krj": "Gagmay nga kayumanggi ukon itom nga mansa sa panit it uyas kon diin nagkaon ang insekto (pecky rice).",
    },
    "A strong, unpleasant smell when walking through the field.": {
        "fil": "Matapang at hindi kanais-nais na amoy kapag naglalakad sa bukid.",
        "krj": "Mabaskog kag malain nga baho kon nagalakat sa uma.",
    },
    "The central leaf of a tiller dries and turns brown while the outer leaves stay green. "
    "It pulls out easily and the base is chewed.": {
        "fil": "Natutuyo at nagiging kayumanggi ang gitnang dahon ng suwi habang berde pa ang mga panlabas na dahon. "
               "Madali itong mabunot at ngatngat ang puno.",
        "krj": "Nagauga kag nagakayumanggi ang tunga nga dahon it suwi samtang berde pa ang mga sa guwa nga dahon. "
               "Madali dya mabunot kag ginkutkot ang puno.",
    },
    "Panicles that stay white or straw-coloured, upright and empty. "
    "They pull out easily because the stem below was cut by the larva.": {
        "fil": "Uhay na nananatiling puti o kulay-dayami, nakatayo at walang laman. "
               "Madaling mabunot dahil pinutol ng uod ang tangkay sa ibaba.",
        "krj": "Uhay nga nagapabilin nga puti ukon kolor-dagami, nakatindog kag wara sulod. "
               "Madali mabunot tungod gin-utod it ulod ang tangkay sa idalom.",
    },
    "Small holes in the stems, sometimes with sawdust-like droppings (frass).": {
        "fil": "Maliliit na butas sa tangkay, minsan may dumi na parang kusot (frass).",
        "krj": "Gagmay nga buho sa tangkay, kis-a may tai nga pareho it kusot (frass).",
    },
    # ---- damage indicators (exact values the reviewer ticks; app/levels.py)
    "Hopperburn (yellowing and drying patches)": {
        "fil": "Hopperburn (naninilaw at natutuyong bahagi)", "krj": "Hopperburn (nagadulaw kag nagauga nga parte)"},
    "Honeydew or sooty mold at the plant base": {
        "fil": "Honeydew o itim na amag sa puno ng halaman", "krj": "Honeydew ukon itom nga agup-op sa puno it tanum"},
    "Plants wilting or lodging": {"fil": "Nalalanta o natutumbang palay", "krj": "Nagalaya ukon nagatumba nga humay"},
    "Yellow-orange leaf discoloration (possible tungro)": {
        "fil": "Dilaw-kahel na kulay ng dahon (posibleng tungro)", "krj": "Dulaw-kahel nga kolor it dahon (posible nga tungro)"},
    "Offensive rice-bug odor in the field": {"fil": "Mabahong amoy ng atangya sa bukid", "krj": "Malain nga baho it tiyangaw sa uma"},
    "Deadhearts (dead central tiller)": {"fil": "Deadheart (patay na gitnang suwi)", "krj": "Deadheart (patay nga tunga nga suwi)"},
    "Whiteheads (empty white panicles)": {"fil": "Whitehead (puting uhay na walang laman)", "krj": "Whitehead (puti nga uhay nga wara sulod)"},
    "Bore holes or frass on stems": {"fil": "Butas o dumi ng uod sa tangkay", "krj": "Buho ukon tai it ulod sa tangkay"},
    "Visible feeding damage on leaves": {"fil": "Kitang pinsala ng pagkain sa dahon", "krj": "Makita nga danyos it pagkaon sa dahon"},
    "Plants wilting or dying": {"fil": "Nalalanta o namamatay na halaman", "krj": "Nagalaya ukon nagapatay nga tanum"},
    "Damage spread across much of the field": {"fil": "Kalat ang pinsala sa malaking bahagi ng bukid", "krj": "Lapta ang danyos sa dako nga parte it uma"},
    # ---- glossary terms and meanings
    "Observation": {"fil": "Obserbasyon", "krj": "Obserbasyon"},
    "A photo and details sent from one field on one day.": {
        "fil": "Isang litrato at detalye mula sa isang bukid sa isang araw.",
        "krj": "Isa ka litrato kag detalye halin sa isa ka uma sa isa ka adlaw."},
    "Validated": {"fil": "Na-validate", "krj": "Na-validate"},
    "A technician or agriculturist checked the observation and confirmed the pest, count and level.": {
        "fil": "Sinuri ng technician o agriculturist ang obserbasyon at kinumpirma ang peste, bilang at antas.",
        "krj": "Gin-usisa it technician ukon agriculturist ang obserbasyon kag ginkumpirma ang peste, kadamuon kag lebel."},
    "Not Validated": {"fil": "Hindi pa Na-validate", "krj": "Wara pa Na-validate"},
    "Waiting for the first review by a technician (or an agriculturist where no technician covers the area).": {
        "fil": "Naghihintay ng unang pagsusuri ng technician (o agriculturist kung walang technician sa lugar).",
        "krj": "Nagahulat it una nga pag-usisa it technician (ukon agriculturist kon wara it technician sa lugar)."},
    "To Be Validated": {"fil": "Ive-validate pa", "krj": "Pagavalidaron pa"},
    "Sent up by a technician for an agriculturist to decide (escalated).": {
        "fil": "Ipinasa ng technician para pagpasyahan ng agriculturist (escalated).",
        "krj": "Ginpasa it technician para desisyunan it agriculturist (escalated)."},
    "Infestation level": {"fil": "Antas ng peste", "krj": "Lebel it peste"},
    "LOW, MEDIUM or HIGH, confirmed by the reviewer from the count, the crop stage and the damage seen.": {
        "fil": "MABABA, KATAMTAMAN o MATAAS, kinumpirma ng nagsuri batay sa bilang, yugto ng palay at nakitang pinsala.",
        "krj": "MANUBO, TUNGA-TUNGA ukon MATAAS, ginkumpirma it nag-usisa base sa kadamuon, yugto it humay kag nakita nga danyos."},
    "Provisional": {"fil": "Pansamantala", "krj": "Temporaryo"},
    "Not yet confirmed by an expert; may change.": {
        "fil": "Hindi pa kinukumpirma ng eksperto; maaaring magbago.",
        "krj": "Wara pa ginkumpirma it eksperto; pwede magbag-o."},
    "Recommendation": {"fil": "Rekomendasyon", "krj": "Rekomendasyon"},
    "An option from the approved treatment list that the reviewer suggests. It is not something you did yet.": {
        "fil": "Opsyon mula sa aprubadong listahan ng lunas na iminumungkahi ng nagsuri. Hindi pa ito ang ginawa mo.",
        "krj": "Opsyon halin sa aprobado nga listahan it bulong nga ginasuhestiyon it nag-usisa. Indi pa dya ang ginhimo mo."},
    "Treatment applied": {"fil": "Lunas na ginawa", "krj": "Bulong nga ginhimo"},
    "What you actually did in the field, and the date you did it.": {
        "fil": "Ang talagang ginawa mo sa bukid at ang petsa nito.",
        "krj": "Ang matuod nga ginhimo mo sa uma kag ang petsa sini."},
    "Follow-up": {"fil": "Follow-up", "krj": "Follow-up"},
    "A new photo of the same field after a treatment, normally 7 days later, to see how it changed.": {
        "fil": "Bagong litrato ng parehong bukid pagkatapos ng lunas, karaniwang makalipas ang 7 araw, para makita ang pagbabago.",
        "krj": "Bag-o nga litrato it pareho nga uma pagkatapos it bulong, kasarangan pagkatapos it 7 ka adlaw, para makita ang pagbag-o."},
    "Hotspot": {"fil": "Hotspot", "krj": "Hotspot"},
    "A barangay with validated cases in the last 30 days.": {
        "fil": "Barangay na may na-validate na kaso sa nakaraang 30 araw.",
        "krj": "Barangay nga may na-validate nga kaso sa nagligad nga 30 ka adlaw."},
    "Direction of spread": {"fil": "Direksyon ng pagkalat", "krj": "Direksyon it paglapta"},
    "Where validated cases moved between two periods. It describes what was reported, not a forecast.": {
        "fil": "Kung saan lumipat ang mga na-validate na kaso sa pagitan ng dalawang panahon. Paglalarawan ito ng naiulat, hindi hula.",
        "krj": "Kon diin naghalin ang mga na-validate nga kaso sa tunga it duha ka panahon. Paglarawan dya it gin-report, indi hula."},
    "Land type": {"fil": "Uri ng lupa", "krj": "Klase it duta"},
    "Upland, rainfed lowland or irrigated lowland. The 100 m elevation hint is provisional.": {
        "fil": "Upland, sahod-ulan na mababang lupa o patubig na mababang lupa. Pansamantala ang 100 m na palatandaan ng taas.",
        "krj": "Upland, sahod-uran nga manubo nga duta ukon ginapatubigan nga manubo nga duta. Temporaryo ang 100 m nga palatandaan it kataason."},
    "Possibly unrelated photo": {"fil": "Posibleng hindi kaugnay na litrato", "krj": "Posible nga indi angot nga litrato"},
    "The photo may not show a rice plant or field; a technician checks it. It is not the same as \"no pests found\".": {
        "fil": "Maaaring hindi palay o bukid ang nasa litrato; sinusuri ito ng technician. Hindi ito katulad ng \"walang nakitang peste\".",
        "krj": "Pwede indi humay ukon uma ang sa litrato; ginausisa dya it technician. Indi dya pareho sa \"wara it nakita nga peste\"."},
}
