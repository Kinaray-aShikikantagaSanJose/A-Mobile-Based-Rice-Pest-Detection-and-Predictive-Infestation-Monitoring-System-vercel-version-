"""Languages on the server: notification texts in English, Filipino and
Kinaray-a (Antique).

Screens are translated in the apps themselves (they also translate the
server's error messages, which stay in English here). Notifications are the
exception: they are written once, when something happens, so they are saved
in the language the recipient chose (users.preferred_language).
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
