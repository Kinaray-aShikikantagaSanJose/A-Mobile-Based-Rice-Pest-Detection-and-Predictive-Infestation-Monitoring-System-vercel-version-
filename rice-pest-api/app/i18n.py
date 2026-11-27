"""Languages on the server: notification texts in English, Filipino and
Kinaray-a (Antique).

Screens are translated in the apps themselves (they also translate the
server's error messages, which stay in English here). The server translates
what it writes itself:
  * notifications, saved once in the recipient's language
    (users.preferred_language);
  * dynamic text it computes on request (directional spread, level
    suggestion reasons, the guide, CSV export headers and values), in the
    language the request asks for (request_language()).

Translations are machine-assisted and NOT expert-reviewed; see
docs/GLOSSARY.md. Internal codes (statuses, pest keys, land type keys) are
never translated, only their labels.
"""
from typing import Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import schema

LANGUAGES = ("en", "fil", "krj")
DEFAULT = "en"

# key -> {lang: text}. {placeholders} are filled by render().
MESSAGES = {
    "returned.title": {
        "en": "Please retake the photo",
        "fil": "Pakikuha ulit ang litrato",
        "krj": "Palihog kuhaan liwan ang litrato",
    },
    "escalated.title": {
        "en": "Sent to an agriculturist",
        "fil": "Ipinasa sa agriculturist",
        "krj": "Ginpasa sa agriculturist",
    },
    "escalated.body": {
        "en": "Your observation needs a closer look. An agriculturist will review it.",
        "fil": "Kailangang suriing mabuti ang iyong obserbasyon. Susuriin ito ng isang agriculturist.",
        "krj": "Kinahanglan usisaon it mayad ang imo nga obserbasyon. Usisaon dya it agriculturist.",
    },
    "validated.title": {
        "en": "Validated: {pest}, {level} infestation",
        "fil": "Na-validate: {pest}, {level} na antas ng peste",
        "krj": "Na-validate: {pest}, {level} nga lebel it peste",
    },
    "validated.body_guidance": {
        "en": "Open the record to see the guidance and your treatment options.",
        "fil": "Buksan ang rekord para makita ang payo at mga lunas na pwede mong gawin.",
        "krj": "Buksi ang rekord para makita ang tugon kag mga bulong nga pwede mo himuon.",
    },
    "validated.body": {
        "en": "Open the record to see your treatment options.",
        "fil": "Buksan ang rekord para makita ang mga lunas na pwede mong gawin.",
        "krj": "Buksi ang rekord para makita ang mga bulong nga pwede mo himuon.",
    },
    "disease.title_level": {
        "en": "Disease report reviewed: {level} level",
        "fil": "Nasuri na ang ulat ng sakit: {level} na antas",
        "krj": "Nausisa run ang report it balatian: {level} nga lebel",
    },
    "disease.title_diagnosis": {
        "en": "Diagnosis and guidance are ready",
        "fil": "Handa na ang diagnosis at payo",
        "krj": "Handa run ang diagnosis kag tugon",
    },
    "disease.body": {
        "en": "Open the record to see what the technician found.",
        "fil": "Buksan ang rekord para makita ang nakita ng technician.",
        "krj": "Buksi ang rekord para makita ang nakita it technician.",
    },
    "account.updated.title": {
        "en": "Your account details were updated",
        "fil": "Na-update ang detalye ng iyong account",
        "krj": "Na-update ang detalye it imo nga account",
    },
    "account.updated.body": {
        "en": "An agriculturist updated your {fields}. Pull down on Home to see the changes.",
        "fil": "In-update ng agriculturist ang iyong {fields}. Hilahin pababa ang Home para makita.",
        "krj": "Gin-update it agriculturist ang imo nga {fields}. Gubuta pababa ang Home para makita.",
    },
    "follow_up.title": {
        "en": "Follow-up date changed",
        "fil": "Binago ang petsa ng follow-up",
        "krj": "Ginbag-o ang petsa it follow-up",
    },
    "follow_up.body": {
        "en": "{who} asks you to check the field after \"{treatment}\" on {date}.",
        "fil": "Pinapasuri ni {who} ang iyong palayan pagkatapos ng \"{treatment}\" sa {date}.",
        "krj": "Ginapausisa ni {who} ang imo nga uma pagkatapos it \"{treatment}\" sa {date}.",
    },
    "recommend_again.title": {
        "en": "Treatment recommended again",
        "fil": "Inirekomenda ulit ang lunas",
        "krj": "Ginrekomenda liwan ang bulong",
    },
    "recommend_again.body": {
        "en": "{who} put \"{treatment}\" back in your treatment options.",
        "fil": "Ibinalik ni {who} ang \"{treatment}\" sa iyong mga lunas.",
        "krj": "Ginbalik ni {who} ang \"{treatment}\" sa imo nga mga bulong.",
    },
    "who.technician": {"en": "Your technician", "fil": "Ang iyong technician", "krj": "Ang imo nga technician"},
    "who.agriculturist": {"en": "Your agriculturist", "fil": "Ang iyong agriculturist", "krj": "Ang imo nga agriculturist"},
    "deleted.title": {
        "en": "An observation was removed",
        "fil": "May obserbasyong binura",
        "krj": "May obserbasyon nga ginpanas",
    },
    "deleted.body": {
        "en": "Observation #{id} from {date} was removed by {who}.",
        "fil": "Ang obserbasyon #{id} noong {date} ay binura ni {who}.",
        "krj": "Ang obserbasyon #{id} kang {date} ginpanas ni {who}.",
    },
    "deleted.body_reason": {
        "en": "Observation #{id} from {date} was removed by {who}. Reason: {reason}",
        "fil": "Ang obserbasyon #{id} noong {date} ay binura ni {who}. Dahilan: {reason}",
        "krj": "Ang obserbasyon #{id} kang {date} ginpanas ni {who}. Rason: {reason}",
    },
    "role.technician": {"en": "a technician", "fil": "isang technician", "krj": "isa ka technician"},
    "role.agriculturist": {"en": "an agriculturist", "fil": "isang agriculturist", "krj": "isa ka agriculturist"},
    "level.LOW": {"en": "low", "fil": "mababa", "krj": "manubo"},
    "level.MEDIUM": {"en": "medium", "fil": "katamtaman", "krj": "tunga-tunga"},
    "level.HIGH": {"en": "high", "fil": "mataas", "krj": "mataas"},
    "field.name": {"en": "name", "fil": "pangalan", "krj": "ngaran"},
    "field.mobile number": {"en": "mobile number", "fil": "numero ng cellphone", "krj": "numero it cellphone"},
    "field.municipality": {"en": "municipality", "fil": "munisipyo", "krj": "banwa"},
    "field.barangay": {"en": "barangay", "fil": "barangay", "krj": "barangay"},
    "field.coverage area": {"en": "coverage area", "fil": "sakop na lugar", "krj": "sakop nga lugar"},
    "field.password": {"en": "password", "fil": "password", "krj": "password"},
    "field.role": {"en": "role", "fil": "tungkulin", "krj": "role"},
}


def clean(code: Optional[str]) -> str:
    code = (code or "").strip().lower()
    return code if code in LANGUAGES else DEFAULT


def render(key: str, lang: str = DEFAULT, **params) -> str:
    entry = MESSAGES.get(key) or {}
    template = entry.get(clean(lang)) or entry.get(DEFAULT) or key
    try:
        return template.format(**params)
    except (KeyError, IndexError):
        return template


def language_of(db: Session, email: str) -> str:
    """The recipient's chosen language (English before the migration)."""
    if not email or not schema.language_ready(db):
        return DEFAULT
    try:
        return clean(db.execute(
            text("SELECT preferred_language FROM users WHERE email = :e"), {"e": email}
        ).scalar())
    except Exception:
        return DEFAULT


def request_language(request=None, user: Optional[dict] = None, lang: Optional[str] = None) -> str:
    """The language for text computed on request: ?lang=, then the
    X-Palay-Language header, then the account's choice, then English."""
    if lang and lang.strip().lower() in LANGUAGES:
        return lang.strip().lower()
    header = (request.headers.get("x-palay-language", "") if request is not None else "").strip().lower()
    if header in LANGUAGES:
        return header
    return clean((user or {}).get("language"))


def t(text_: str, lang: str = DEFAULT, **params) -> str:
    """Translate a label by its English text (LABELS); unknown text is kept."""
    entry = LABELS.get(text_)
    template = (entry or {}).get(clean(lang)) or text_
    try:
        return template.format(**params) if params else template
    except (KeyError, IndexError):
        return template


MESSAGES.update({
    "validated.body_recommended": {
        "en": "Your technician recommended treatment options. Open the record to see them.",
        "fil": "May inirekomendang lunas ang iyong technician. Buksan ang rekord para makita.",
        "krj": "May ginrekomenda nga bulong ang imo nga technician. Buksi ang rekord para makita.",
    },
    # ---- directional spread (app/insights.py)
    "spread.moved": {
        "en": "Reported cases moved toward the {direction} between {p1} and {p2}.",
        "fil": "Lumipat ang mga naiulat na kaso papuntang {direction} mula {p1} hanggang {p2}.",
        "krj": "Naghalin ang mga gin-report nga kaso pakadto sa {direction} halin {p1} tubtob {p2}.",
    },
    "spread.still": {
        "en": "Reported cases stayed in about the same area between {p1} and {p2}.",
        "fil": "Nanatili sa halos parehong lugar ang mga naiulat na kaso mula {p1} hanggang {p2}.",
        "krj": "Nagpabilin sa halos pareho nga lugar ang mga gin-report nga kaso halin {p1} tubtob {p2}.",
    },
    "spread.insufficient": {
        "en": "Direction cannot be determined: not enough validated cases with a reliable location.",
        "fil": "Hindi matukoy ang direksyon: kulang ang na-validate na kaso na may maaasahang lokasyon.",
        "krj": "Indi matukoy ang direksyon: kulang ang na-validate nga kaso nga may masaligan nga lokasyon.",
    },
    "spread.counts": {
        "en": "{n1} cases in {p1}, {n2} in {p2} (at least {min} needed in each).",
        "fil": "{n1} kaso sa {p1}, {n2} sa {p2} (kailangan ng hindi bababa sa {min} bawat isa).",
        "krj": "{n1} ka kaso sa {p1}, {n2} sa {p2} (kinahanglan indi magnubo sa {min} kada isa).",
    },
    "spread.distance": {"en": "About {distance}.", "fil": "Mga {distance}.", "krj": "Mga {distance}."},
    "spread.summary_places": {
        "en": "{direction} — from Brgy. {from_brgy} to Brgy. {to_brgy}",
        "fil": "{direction} — mula Brgy. {from_brgy} hanggang Brgy. {to_brgy}",
        "krj": "{direction} — halin sa Brgy. {from_brgy} pakadto sa Brgy. {to_brgy}",
    },
    "spread.summary_no_places": {
        "en": "{direction} — the barangays cannot be determined",
        "fil": "{direction} — hindi matukoy ang mga barangay",
        "krj": "{direction} — indi matukoy ang mga barangay",
    },
    "spread.summary_still": {
        "en": "No clear movement — around Brgy. {brgy}",
        "fil": "Walang malinaw na paggalaw — sa paligid ng Brgy. {brgy}",
        "krj": "Wara it malinaw nga paghulag — sa palibot it Brgy. {brgy}",
    },
    "spread.summary_still_unknown": {
        "en": "No clear movement", "fil": "Walang malinaw na paggalaw", "krj": "Wara it malinaw nga paghulag",
    },
    "spread.summary_insufficient": {"en": "Cannot be determined", "fil": "Hindi matukoy", "krj": "Indi matukoy"},
    "spread.note": {
        "en": "Based on validated cases with a reliable location only. It shows observed movement, not a forecast.",
        "fil": "Batay lamang sa mga na-validate na kaso na may maaasahang lokasyon. "
               "Ipinapakita nito ang naobserbahang paggalaw, hindi hula.",
        "krj": "Base lang sa mga na-validate nga kaso nga may masaligan nga lokasyon. "
               "Ginapakita dya ang naobserbahan nga paghulag, indi hula.",
    },
    "period.1": {"en": "Period 1", "fil": "Panahon 1", "krj": "Panahon 1"},
    "period.2": {"en": "Period 2", "fil": "Panahon 2", "krj": "Panahon 2"},
    "dir.N": {"en": "North", "fil": "Hilaga", "krj": "Aminhan"},
    "dir.NE": {"en": "Northeast", "fil": "Hilagang-silangan", "krj": "Aminhan-sidlangan"},
    "dir.E": {"en": "East", "fil": "Silangan", "krj": "Sidlangan"},
    "dir.SE": {"en": "Southeast", "fil": "Timog-silangan", "krj": "Bagatnan-sidlangan"},
    "dir.S": {"en": "South", "fil": "Timog", "krj": "Bagatnan"},
    "dir.SW": {"en": "Southwest", "fil": "Timog-kanluran", "krj": "Bagatnan-nakatundan"},
    "dir.W": {"en": "West", "fil": "Kanluran", "krj": "Nakatundan"},
    "dir.NW": {"en": "Northwest", "fil": "Hilagang-kanluran", "krj": "Aminhan-nakatundan"},
    # ---- level suggestion reasons (app/levels.py)
    "reason.count": {
        "en": "Count {count}: {level} for {stage} (MEDIUM from {medium}, HIGH from {high})",
        "fil": "Bilang {count}: {level} para sa {stage} (KATAMTAMAN mula {medium}, MATAAS mula {high})",
        "krj": "Kadamuon {count}: {level} para sa {stage} (TUNGA-TUNGA halin {medium}, MATAAS halin {high})",
    },
    "reason.no_count": {
        "en": "No reliable count, so the suggestion starts at LOW and rests on the damage you saw",
        "fil": "Walang maaasahang bilang, kaya nagsisimula sa MABABA at nakabatay sa pinsalang nakita mo",
        "krj": "Wara it masaligan nga kadamuon, gani nagasugod sa MANUBO kag base sa danyos nga nakita mo",
    },
    "reason.no_thresholds": {
        "en": "No thresholds set for this pest, so the suggestion starts at LOW",
        "fil": "Walang threshold para sa pesteng ito, kaya nagsisimula sa MABABA",
        "krj": "Wara it threshold para sa peste nga dya, gani nagasugod sa MANUBO",
    },
    "reason.indicator": {"en": "+1 level: {indicator}", "fil": "+1 antas: {indicator}", "krj": "+1 lebel: {indicator}"},
    "reason.provisional": {
        "en": "These thresholds are provisional until an agriculturist confirms them.",
        "fil": "Pansamantala ang mga threshold na ito hangga't hindi kinukumpirma ng agriculturist.",
        "krj": "Temporaryo pa ang mga threshold nga dya hasta indi pa ginakumpirma it agriculturist.",
    },
    "stage.any": {"en": "any stage", "fil": "anumang yugto", "krj": "bisan ano nga yugto"},
})

# Labels by their English text (exports, guide, computed values).
LABELS = {
    # statuses and queues (codes stay as they are in the database)
    "Not Validated": {"fil": "Hindi pa Na-validate", "krj": "Wara pa Na-validate"},
    "To Be Validated": {"fil": "Ive-validate pa", "krj": "Pagavalidaron pa"},
    "Validated": {"fil": "Na-validate", "krj": "Na-validate"},
    "Returned": {"fil": "Ibinalik", "krj": "Ginbalik"},
    "No pests found": {"fil": "Walang nakitang peste", "krj": "Wara it nakita nga peste"},
    "Possibly unrelated photo": {"fil": "Posibleng hindi kaugnay na litrato", "krj": "Posible nga indi angot nga litrato"},
    "Relevant": {"fil": "Kaugnay", "krj": "Angot"},
    "Not checked": {"fil": "Hindi nasuri", "krj": "Wara nausisa"},
    # levels
    "LOW": {"fil": "MABABA", "krj": "MANUBO"},
    "MEDIUM": {"fil": "KATAMTAMAN", "krj": "TUNGA-TUNGA"},
    "HIGH": {"fil": "MATAAS", "krj": "MATAAS"},
    # pests and report types (English name kept in brackets where the local
    # name is less known, so the label stays recognisable)
    "Brown Planthopper": {"fil": "Brown planthopper (kayumangging hanip)", "krj": "Brown planthopper (kayumanggi nga hanip)"},
    "Green Leafhopper": {"fil": "Green leafhopper (berdeng leafhopper)", "krj": "Green leafhopper (berde nga leafhopper)"},
    "Rice Bug": {"fil": "Atangya (rice bug)", "krj": "Tiyangaw (rice bug)"},
    "Rice Stem Borer": {"fil": "Aksip (stem borer)", "krj": "Uod sa tangkay (stem borer)"},
    "Outside the supported pests": {"fil": "Hindi kasama sa apat na peste", "krj": "Indi kaupod sa apat nga peste"},
    "Disease report": {"fil": "Ulat ng sakit", "krj": "Report it balatian"},
    "Unidentified": {"fil": "Hindi pa natukoy", "krj": "Wara pa natukoy"},
    "Not identified yet": {"fil": "Hindi pa natukoy", "krj": "Wara pa natukoy"},
    # land types
    "Upland": {"fil": "Upland (mataas na lupa)", "krj": "Upland (mataas nga duta)"},
    "Rainfed lowland": {"fil": "Sahod-ulan na mababang lupa", "krj": "Sahod-uran nga manubo nga duta"},
    "Irrigated lowland": {"fil": "Patubig na mababang lupa", "krj": "Ginapatubigan nga manubo nga duta"},
    "Not recorded": {"fil": "Hindi naitala", "krj": "Wara narekord"},
    # crop stages
    "Vegetative": {"fil": "Vegetative (paglaki ng dahon at suwi)", "krj": "Vegetative (pagtubo it dahon kag suwi)"},
    "Reproductive": {"fil": "Reproductive (pagbubuntis hanggang pamumulaklak)", "krj": "Reproductive (pagbusong tubtob pagbulak)"},
    "Ripening": {"fil": "Ripening (paghinog ng butil)", "krj": "Ripening (paghinog it uyas)"},
    # outcomes
    "improved": {"fil": "bumuti", "krj": "nagmayad"},
    "no change": {"fil": "walang pagbabago", "krj": "wara it pagbag-o"},
    "worsened": {"fil": "lumala", "krj": "naglala"},
    "not comparable": {"fil": "hindi maihahambing", "krj": "indi maikumparar"},
    "awaiting follow-up": {"fil": "hinihintay ang follow-up", "krj": "ginahulat ang follow-up"},
    "overdue": {"fil": "lampas na sa takdang petsa", "krj": "lapas run sa petsa"},
    "follow-up in review": {"fil": "sinusuri pa ang follow-up", "krj": "ginausisa pa ang follow-up"},
    # trends
    "increasing": {"fil": "tumataas", "krj": "nagataas"},
    "decreasing": {"fil": "bumababa", "krj": "nagamanubo"},
    "stable": {"fil": "matatag", "krj": "pareho"},
    "pests": {"fil": "bilang ng peste", "krj": "kadamuon it peste"},
    "records": {"fil": "bilang ng rekord", "krj": "kadamuon it rekord"},
    "yes": {"fil": "oo", "krj": "huo"},
    "no": {"fil": "hindi", "krj": "indi"},
    "not countable": {"fil": "hindi mabilang", "krj": "indi maisip"},
    "pest": {"fil": "peste", "krj": "peste"},
    "disease": {"fil": "sakit", "krj": "balatian"},
    "Pattern in past records, not a forecast": {
        "fil": "Pattern sa mga nakaraang rekord, hindi hula", "krj": "Pattern sa mga nagligad nga rekord, indi hula"},
    # export headers
    "Observation ID": {"fil": "ID ng obserbasyon", "krj": "ID it obserbasyon"},
    "Date": {"fil": "Petsa", "krj": "Petsa"},
    "Municipality": {"fil": "Munisipyo", "krj": "Banwa"},
    "Barangay": {"fil": "Barangay", "krj": "Barangay"},
    "Submitted by": {"fil": "Ipinasa ni", "krj": "Ginpasa ni"},
    "Type": {"fil": "Uri", "krj": "Klase"},
    "Pest": {"fil": "Peste", "krj": "Peste"},
    "Count": {"fil": "Bilang", "krj": "Kadamuon"},
    "Infestation level": {"fil": "Antas ng peste", "krj": "Lebel it peste"},
    "Crop stage": {"fil": "Yugto ng palay", "krj": "Yugto it humay"},
    "Land type": {"fil": "Uri ng lupa", "krj": "Klase it duta"},
    "Monitoring method": {"fil": "Paraan ng pagmamanman", "krj": "Paagi it pagbantay"},
    "Status": {"fil": "Katayuan", "krj": "Kahimtangan"},
    "Photo check": {"fil": "Pagsuri ng litrato", "krj": "Pag-usisa it litrato"},
    "Validated by": {"fil": "Na-validate ni", "krj": "Na-validate ni"},
    "Validated at": {"fil": "Petsa ng pag-validate", "krj": "Petsa it pag-validate"},
    "Diagnosis": {"fil": "Diagnosis", "krj": "Diagnosis"},
    "Guidance": {"fil": "Payo", "krj": "Tugon"},
    "Recommended options": {"fil": "Inirekomendang lunas", "krj": "Ginrekomenda nga bulong"},
    "Latitude": {"fil": "Latitude", "krj": "Latitude"},
    "Longitude": {"fil": "Longitude", "krj": "Longitude"},
    "Month": {"fil": "Buwan", "krj": "Bulan"},
    "Breakdown": {"fil": "Hati", "krj": "Pagbahin"},
    "Name": {"fil": "Pangalan", "krj": "Ngaran"},
    "Validated observations": {"fil": "Na-validate na obserbasyon", "krj": "Na-validate nga obserbasyon"},
    "Pests counted": {"fil": "Bilang ng peste", "krj": "Kadamuon it peste"},
    "Quarter": {"fil": "Kwarter", "krj": "Kwarter"},
    "Compared by": {"fil": "Inihambing ayon sa", "krj": "Ginkumpara base sa"},
    "This quarter": {"fil": "Ngayong kwarter", "krj": "Dya nga kwarter"},
    "Previous quarter": {"fil": "Nakaraang kwarter", "krj": "Nagligad nga kwarter"},
    "Same quarter last year": {"fil": "Parehong kwarter noong nakaraang taon", "krj": "Pareho nga kwarter kang nagligad nga tuig"},
    "Change %": {"fil": "Pagbabago %", "krj": "Pagbag-o %"},
    "Pattern": {"fil": "Pattern", "krj": "Pattern"},
    "Recurring": {"fil": "Umuulit", "krj": "Nagaliwat"},
    "Note": {"fil": "Tala", "krj": "Tala"},
    "Treatment ID": {"fil": "ID ng lunas", "krj": "ID it bulong"},
    "Farmer": {"fil": "Magsasaka", "krj": "Mangunguma"},
    "Treatment applied": {"fil": "Lunas na ginawa", "krj": "Bulong nga ginhimo"},
    "Applied": {"fil": "Petsa ng paglalapat", "krj": "Petsa it pagbutang"},
    "Follow-up due": {"fil": "Takdang follow-up", "krj": "Petsa it follow-up"},
    "Observed before": {"fil": "Petsa bago", "krj": "Petsa antes"},
    "Level before": {"fil": "Antas bago", "krj": "Lebel antes"},
    "Count before": {"fil": "Bilang bago", "krj": "Kadamuon antes"},
    "Follow-up observation": {"fil": "Follow-up na obserbasyon", "krj": "Follow-up nga obserbasyon"},
    "Observed after": {"fil": "Petsa pagkatapos", "krj": "Petsa pagkatapos"},
    "Level after": {"fil": "Antas pagkatapos", "krj": "Lebel pagkatapos"},
    "Count after": {"fil": "Bilang pagkatapos", "krj": "Kadamuon pagkatapos"},
    "Outcome": {"fil": "Resulta", "krj": "Resulta"},
    "Outcome basis": {"fil": "Batayan ng resulta", "krj": "Basehan it resulta"},
    "Recommended by reviewer": {"fil": "Inirekomenda ng nagsuri", "krj": "Ginrekomenda it nag-usisa"},
}

from .i18n_guide import GUIDE_LABELS  # noqa: E402  (guide text, indicators, glossary)

LABELS.update(GUIDE_LABELS)
