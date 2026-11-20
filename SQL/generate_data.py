import os
import psycopg
from datetime import datetime, date, timedelta

# Default password hash for "$2b$12$JziSefgAilG7GUY2I9YC5.og81EN0QhEkk9UzmCdJT7WKx/WCal1."
PASSWORD_HASH = "$2b$12$JziSefgAilG7GUY2I9YC5.og81EN0QhEkk9UzmCdJT7WKx/WCal1."

MUNICIPALITIES_DATA = [
    {
        "name": "Anini-y",
        "lat": 10.4312, "lng": 121.9268,
        "barangays": ["Poblacion", "Casay", "San Casimiro", "Mabini"],
        "farmer_name": "Juanito Delgado", "farmer_email": "juanito.aniniy@antique.gov.ph",
        "phone": "+63 917 111 0101",
        "scans": [
            {
                "pest": "brown_planthopper", "crop_stage": "Vegetative", "count": 14, "severity": "HIGH",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Hopperburn patches beginning to spread from bund borders.",
                "symptoms": "Yellowing leaf tips, hopper aggregation at base",
                "indicators": ["Hopperburn (yellowing and drying patches)", "Honeydew or sooty mold at the plant base"],
                "diagnosis": "Severe brown planthopper aggregation threatening vegetative tillers.",
                "guidance": "Immediately apply intermittent drying (AWD) for 4 days. Avoid nitrogen topdressing.",
                "days_ago": 12, "treatment_type": "cultural",
                "treatment_text": "Alternate Wetting and Drying - Drained field for 4 days to expose hopper nymphs",
                "has_followup": True, "followup_count": 3
            },
            {
                "pest": "rice_bug", "crop_stage": "Reproductive", "count": 6, "severity": "MEDIUM",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Adult bugs observed feeding on flowering panicles.",
                "symptoms": "Unfilled spikelets and grain discoloration",
                "indicators": ["Empty or unfilled grains", "Brown spots on grains"],
                "diagnosis": "Moderate rice bug population feeding during heading.",
                "guidance": "Deploy odorous snail/fish attractant traps along dikes. Hand net adults at dawn.",
                "days_ago": 6, "treatment_type": "ecological",
                "treatment_text": "Set up 10 decaying snail bait traps along dikes and sweep netted at dawn",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Tobias Fornier",
        "lat": 10.5180, "lng": 122.0210,
        "barangays": ["Poblacion Sur", "Diclum", "Igdalaguit", "Ballenas"],
        "farmer_name": "Elena Alvañiz", "farmer_email": "elena.tobias@antique.gov.ph",
        "phone": "+63 917 111 0102",
        "scans": [
            {
                "pest": "rice_stem_borer", "crop_stage": "Vegetative", "count": 5, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Pheromone Trap",
                "notes": "Deadheart tillers spotted across several hills.",
                "symptoms": "Drying central tillers easily pulled from stem",
                "indicators": ["Deadhearts (dead central tiller)"],
                "diagnosis": "Early yellow stem borer larval damage.",
                "guidance": "Deploy Trichogramma japonicum parasitoid cards at 50 cards/ha.",
                "days_ago": 15, "treatment_type": "biological",
                "treatment_text": "Released 40 Trichogramma japonicum egg parasitoid cards across the 1-ha plot",
                "has_followup": True, "followup_count": 1
            },
            {
                "pest": "green_leafhopper", "crop_stage": "Vegetative", "count": 2, "severity": "LOW",
                "status": "pending", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Few leafhoppers on sticky trap; checking for virus symptoms.",
                "symptoms": "Minor leaf yellowing",
                "indicators": [],
                "diagnosis": "",
                "guidance": "",
                "days_ago": 2, "treatment_type": None,
                "has_followup": False
            }
        ]
    },
    {
        "name": "Hamtic",
        "lat": 10.6750, "lng": 121.9820,
        "barangays": ["Guintas", "Malandog", "Caridad", "Funda"],
        "farmer_name": "Roberto Guanzon", "farmer_email": "roberto.hamtic@antique.gov.ph",
        "phone": "+63 917 111 0103",
        "scans": [
            {
                "pest": "brown_planthopper", "crop_stage": "Reproductive", "count": 18, "severity": "HIGH",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "High nymph density at water level; lodging observed in center.",
                "symptoms": "Wilting, hopperburn patches, honeydew",
                "indicators": ["Hopperburn (yellowing and drying patches)", "Plants wilting or lodging"],
                "diagnosis": "Critical BPH outbreak during boot-to-heading transition.",
                "guidance": "Spot-spray approved buprofezin at base of hill. Drain field immediately.",
                "days_ago": 9, "treatment_type": "chemical",
                "treatment_text": "Spot-sprayed pymetrozine at hill bases and drained field for 3 days",
                "has_followup": True, "followup_count": 4
            },
            {
                "pest": "green_leafhopper", "crop_stage": "Vegetative", "count": 4, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Vector monitoring during early tillering.",
                "symptoms": "Slight stunting on border hills",
                "indicators": ["Stunted plants"],
                "diagnosis": "Moderate GLH count; potential tungro risk.",
                "guidance": "Rogue out suspected tungro hills. Establish light traps.",
                "days_ago": 5, "treatment_type": "ecological",
                "treatment_text": "Deployed solar LED light trap on dike from 6 PM to 9 PM",
                "has_followup": False
            }
        ]
    },
    {
        "name": "San Jose de Buenavista",
        "lat": 10.7480, "lng": 121.9420,
        "barangays": ["Funda-Dalipe", "San Pedro", "Maybato Sur", "Madrangca"],
        "farmer_name": "Maria Santos", "farmer_email": "maria.sanjose@antique.gov.ph",
        "phone": "+63 917 111 0104",
        "scans": [
            {
                "pest": "rice_bug", "crop_stage": "Reproductive", "count": 9, "severity": "HIGH",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Bugs feeding heavily on milk-stage grain; distinct offensive odor.",
                "symptoms": "Unfilled spikelets, brown puncture marks",
                "indicators": ["Empty or unfilled grains", "Brown spots on grains", "Offensive rice-bug odor in the field"],
                "diagnosis": "Severe rice bug pressure above economic threshold during grain fill.",
                "guidance": "Conduct evening contact spot spray per technician label. Install bait traps.",
                "days_ago": 7, "treatment_type": "chemical",
                "treatment_text": "Late-afternoon foliar application of approved contact insecticide per RCPC advisory",
                "has_followup": True, "followup_count": 2
            },
            {
                "pest": "green_leafhopper", "crop_stage": "Vegetative", "count": 8, "severity": "HIGH",
                "status": "escalated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Suspected Tungro outbreak in Maybato Sur nursery; high GLH catches.",
                "symptoms": "Intense orange-yellow discoloration and severe plant stunting",
                "indicators": ["Yellow-orange leaf discoloration (possible tungro)", "Stunted plants", "Reduced tillering"],
                "diagnosis": "",
                "guidance": "",
                "days_ago": 1, "treatment_type": None,
                "has_followup": False
            }
        ]
    },
    {
        "name": "Sibalom",
        "lat": 10.7850, "lng": 122.0150,
        "barangays": ["Bongbongan I", "Pis-anan", "Villar", "Grasparil"],
        "farmer_name": "Domingo Villar", "farmer_email": "domingo.sibalom@antique.gov.ph",
        "phone": "+63 917 111 0105",
        "scans": [
            {
                "pest": "rice_stem_borer", "crop_stage": "Reproductive", "count": 7, "severity": "HIGH",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Whiteheads emerging across the entire western paddy block.",
                "symptoms": "Erect white panicles with empty chaff",
                "indicators": ["Whiteheads (empty white panicles)", "Bore holes or frass on stems"],
                "diagnosis": "Significant stem borer whitehead damage at heading.",
                "guidance": "Mark affected area for post-harvest stubble plowing and deep flooding.",
                "days_ago": 14, "treatment_type": "cultural",
                "treatment_text": "Deep plowing of infested stubble and flooded field 7 cm for 10 days post-harvest",
                "has_followup": False
            },
            {
                "pest": "brown_planthopper", "crop_stage": "Vegetative", "count": 11, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Planthoppers multiplying after recent continuous monsoon rain.",
                "symptoms": "Honeydew secretion at base",
                "indicators": ["Honeydew or sooty mold at the plant base"],
                "diagnosis": "BPH nymph buildup in moist canopy.",
                "guidance": "Intermittent drainage; conserve wolf spiders.",
                "days_ago": 8, "treatment_type": "biological",
                "treatment_text": "Conserved wolf spider population by withholding chemical sprays; applied AWD",
                "has_followup": True, "followup_count": 3
            },
            {
                "pest": "rice_bug", "crop_stage": "Ripening", "count": 3, "severity": "LOW",
                "status": "pending", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Few bugs remaining as crop reaches hard dough.",
                "symptoms": "Minor pecky grains",
                "indicators": [],
                "diagnosis": "",
                "guidance": "",
                "days_ago": 1, "treatment_type": None,
                "has_followup": False
            }
        ]
    },
    {
        "name": "Belison",
        "lat": 10.8420, "lng": 122.0350,
        "barangays": ["Poblacion", "Delima", "Maradiona", "Borocboroc"],
        "farmer_name": "Carmen Delima", "farmer_email": "carmen.belison@antique.gov.ph",
        "phone": "+63 917 111 0106",
        "scans": [
            {
                "pest": "green_leafhopper", "crop_stage": "Vegetative", "count": 4, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Leafhoppers present on seedbed borders.",
                "symptoms": "Faint leaf chlorosis",
                "indicators": ["Yellow-orange leaf discoloration (possible tungro)"],
                "diagnosis": "Moderate GLH count on early tillering rice.",
                "guidance": "Scout twice weekly for tungro roguing. Use resistant variety.",
                "days_ago": 11, "treatment_type": "cultural",
                "treatment_text": "Rogued and buried 5 suspicious tungro hills; weeded nursery borders",
                "has_followup": True, "followup_count": 1
            },
            {
                "pest": "brown_planthopper", "crop_stage": "Reproductive", "count": 5, "severity": "LOW",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Trap catches stable; natural enemy counts high.",
                "symptoms": "None",
                "indicators": [],
                "diagnosis": "BPH below economic injury level; well-balanced natural biocontrol.",
                "guidance": "Maintain current water management. No sprays needed.",
                "days_ago": 4, "treatment_type": "biological",
                "treatment_text": "Maintained beneficial mirid bug habitats along field edges",
                "has_followup": False
            }
        ]
    },
    {
        "name": "San Remigio",
        "lat": 10.8020, "lng": 122.1220,
        "barangays": ["Poblacion", "Bagumbayan", "Iguirindon", "General Fullon"],
        "farmer_name": "Mateo Fullon", "farmer_email": "mateo.sanremigio@antique.gov.ph",
        "phone": "+63 917 111 0107",
        "scans": [
            {
                "pest": "rice_stem_borer", "crop_stage": "Vegetative", "count": 8, "severity": "HIGH",
                "status": "validated", "method": "Direct Field Observation", "trap": "Pheromone Trap",
                "notes": "Moth flight peak captured; widespread deadhearts on upland terraces.",
                "symptoms": "Deadhearts, frass on stem nodes",
                "indicators": ["Deadhearts (dead central tiller)", "Bore holes or frass on stems"],
                "diagnosis": "Severe stem borer pressure during vegetative stage.",
                "guidance": "Hand pick egg masses; release Trichogramma cards; spot-treat if above 10%.",
                "days_ago": 10, "treatment_type": "biological",
                "treatment_text": "Hand collected egg clusters and released 50 Trichogramma parasitoid cards",
                "has_followup": True, "followup_count": 2
            },
            {
                "pest": "brown_planthopper", "crop_stage": "Ripening", "count": 12, "severity": "MEDIUM",
                "status": "pending", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Hoppers migrating into late-maturing parcel.",
                "symptoms": "Lower leaf browning",
                "indicators": ["Hopperburn (yellowing and drying patches)"],
                "diagnosis": "",
                "guidance": "",
                "days_ago": 2, "treatment_type": None,
                "has_followup": False
            }
        ]
    },
    {
        "name": "Patnongon",
        "lat": 10.9150, "lng": 122.0150,
        "barangays": ["Poblacion", "Padang", "Aureliana", "Alvañiz"],
        "farmer_name": "Ramon Padang", "farmer_email": "ramon.patnongon@antique.gov.ph",
        "phone": "+63 917 111 0108",
        "scans": [
            {
                "pest": "rice_bug", "crop_stage": "Reproductive", "count": 10, "severity": "HIGH",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Heavy aggregation of rice bugs during milk development.",
                "symptoms": "Empty grains, pungent odor in paddy",
                "indicators": ["Empty or unfilled grains", "Brown spots on grains", "Offensive rice-bug odor in the field"],
                "diagnosis": "Exceeded threshold for rice bug during vulnerable milky stage.",
                "guidance": "Late afternoon targeted spray combined with morning net sweepings.",
                "days_ago": 13, "treatment_type": "ecological",
                "treatment_text": "Installed fish-odor attractant traps and performed sweep netting daily",
                "has_followup": True, "followup_count": 3
            },
            {
                "pest": "green_leafhopper", "crop_stage": "Vegetative", "count": 3, "severity": "LOW",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Low GLH count; crop tillering well.",
                "symptoms": "Normal vegetative appearance",
                "indicators": [],
                "diagnosis": "Low population; continue regular trap monitoring.",
                "guidance": "Maintain bund cleanliness and scout weekly.",
                "days_ago": 6, "treatment_type": "cultural",
                "treatment_text": "Trimmed bund vegetation and weeded irrigation inlets",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Valderrama",
        "lat": 10.9950, "lng": 122.1320,
        "barangays": ["Ubos", "Takas", "Buluangan", "Borocboroc"],
        "farmer_name": "Teresa Buluangan", "farmer_email": "teresa.valderrama@antique.gov.ph",
        "phone": "+63 917 111 0109",
        "scans": [
            {
                "pest": "brown_planthopper", "crop_stage": "Vegetative", "count": 16, "severity": "HIGH",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Dense colonies forming at stem base; river valley humidity is high.",
                "symptoms": "Hopperburn spots, wilting tillers",
                "indicators": ["Hopperburn (yellowing and drying patches)", "Plants wilting or lodging"],
                "diagnosis": "High BPH infestation in inland valley microclimate.",
                "guidance": "Drain water 4 days immediately; apply buprofezin spot spray if counts remain high.",
                "days_ago": 8, "treatment_type": "cultural",
                "treatment_text": "Intermittent drainage applied for 5 days; lowered nitrogen application",
                "has_followup": True, "followup_count": 4
            },
            {
                "pest": "rice_stem_borer", "crop_stage": "Reproductive", "count": 5, "severity": "MEDIUM",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Occasional whiteheads visible in panicle heading.",
                "symptoms": "White panicles with empty hulls",
                "indicators": ["Whiteheads (empty white panicles)"],
                "diagnosis": "Moderate whitehead incidence during panicle emergence.",
                "guidance": "Release egg parasitoids; inspect egg masses for next cycle.",
                "days_ago": 4, "treatment_type": "biological",
                "treatment_text": "Released Trichogramma cards and removed infested panicles",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Bugasong",
        "lat": 11.0420, "lng": 122.0620,
        "barangays": ["Centro Ilawod", "Centro Ilaya", "Tagudtud", "Bagacay"],
        "farmer_name": "Arnaldo Tagudtud", "farmer_email": "arnaldo.bugasong@antique.gov.ph",
        "phone": "+63 917 111 0110",
        "scans": [
            {
                "pest": "rice_bug", "crop_stage": "Ripening", "count": 6, "severity": "MEDIUM",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Bugs feeding on dough stage grain.",
                "symptoms": "Pecky grains, brown spotting on husk",
                "indicators": ["Brown spots on grains"],
                "diagnosis": "Moderate rice bug count at early dough.",
                "guidance": "Morning sweep net collection; maintain bait traps.",
                "days_ago": 9, "treatment_type": "ecological",
                "treatment_text": "Deployed 8 snail bait traps and sweep netted sluggish adults at 6:30 AM",
                "has_followup": True, "followup_count": 2
            },
            {
                "pest": "brown_planthopper", "crop_stage": "Vegetative", "count": 4, "severity": "LOW",
                "status": "returned", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Photo blurred due to camera shake in windy condition.",
                "symptoms": "Unclear",
                "indicators": [],
                "diagnosis": "",
                "guidance": "Photo too blurry to accurately distinguish planthopper instars. Please retake photo with steady lighting.",
                "days_ago": 3, "treatment_type": None,
                "has_followup": False
            }
        ]
    },
    {
        "name": "Laua-an",
        "lat": 11.1450, "lng": 122.0450,
        "barangays": ["Poblacion", "Guiamon", "Casit-an", "Barangay 9"],
        "farmer_name": "Alleah Tejares", "farmer_email": "tejaresalleah@sac.edu.ph",
        "phone": "+63 917 111 0111",
        "scans": [
            {
                "pest": "brown_planthopper", "crop_stage": "Reproductive", "count": 8, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Nymph count increasing during boot stage.",
                "symptoms": "Minor yellowing on lower leaves",
                "indicators": ["Honeydew or sooty mold at the plant base"],
                "diagnosis": "Medium BPH level at critical reproductive stage.",
                "guidance": "AWD drainage 3 days; keep bunds trimmed.",
                "days_ago": 11, "treatment_type": "cultural",
                "treatment_text": "Carried out 3-day field drainage and trimmed bordering wild grasses",
                "has_followup": True, "followup_count": 2
            },
            {
                "pest": "rice_stem_borer", "crop_stage": "Vegetative", "count": 3, "severity": "LOW",
                "status": "validated", "method": "Trap Observation", "trap": "Pheromone Trap",
                "notes": "Low adult moth count in pheromone monitoring trap.",
                "symptoms": "None",
                "indicators": [],
                "diagnosis": "Low population; within safe economic threshold.",
                "guidance": "Continue weekly pheromone trap maintenance.",
                "days_ago": 5, "treatment_type": "ecological",
                "treatment_text": "Refreshed pheromone lure and recorded weekly moth catch",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Barbaza",
        "lat": 11.2150, "lng": 122.0650,
        "barangays": ["Binanu-an", "Esparar", "Maris Ygot", "Jinalinan"],
        "farmer_name": "Florante Esparar", "farmer_email": "florante.barbaza@antique.gov.ph",
        "phone": "+63 917 111 0112",
        "scans": [
            {
                "pest": "green_leafhopper", "crop_stage": "Vegetative", "count": 6, "severity": "HIGH",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Frequent leafhopper catches; neighboring barangay reported tungro cases.",
                "symptoms": "Stunted tillers, leaf tip yellowing",
                "indicators": ["Yellow-orange leaf discoloration (possible tungro)", "Stunted plants"],
                "diagnosis": "High risk of tungro vector transmission during active tillering.",
                "guidance": "Rogue out infected hills; perimeter spot-treatment with imidacloprid.",
                "days_ago": 10, "treatment_type": "chemical",
                "treatment_text": "Treated field perimeter borders with registered systemic neonicotinoid per label",
                "has_followup": True, "followup_count": 1
            },
            {
                "pest": "rice_bug", "crop_stage": "Reproductive", "count": 5, "severity": "MEDIUM",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Early morning sighting on flowering rice panicles.",
                "symptoms": "Pungent odor, grain punctures",
                "indicators": ["Empty or unfilled grains"],
                "diagnosis": "Moderate bug count on flowering rice.",
                "guidance": "Hang odorous meat/snail traps; sweep net adults at daybreak.",
                "days_ago": 4, "treatment_type": "ecological",
                "treatment_text": "Set up 10 bamboo-suspended decaying snail traps around the parcel",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Tibiao",
        "lat": 11.2920, "lng": 122.0350,
        "barangays": ["Poblacion", "Importante", "Malabor", "Tuno"],
        "farmer_name": "Danilo Importante", "farmer_email": "danilo.tibiao@antique.gov.ph",
        "phone": "+63 917 111 0113",
        "scans": [
            {
                "pest": "rice_stem_borer", "crop_stage": "Reproductive", "count": 6, "severity": "HIGH",
                "status": "validated", "method": "Direct Field Observation", "trap": "Pheromone Trap",
                "notes": "Bore holes with frass found on stems near mountain irrigation creek.",
                "symptoms": "Whiteheads and stem lodging",
                "indicators": ["Whiteheads (empty white panicles)", "Bore holes or frass on stems"],
                "diagnosis": "Severe stem borer damage at flowering stage.",
                "guidance": "Release Trichogramma parasitoids; destroy damaged stems post-harvest.",
                "days_ago": 12, "treatment_type": "biological",
                "treatment_text": "Released 45 Trichogramma cards and marked parcel for deep post-harvest stubble plowing",
                "has_followup": True, "followup_count": 2
            },
            {
                "pest": "brown_planthopper", "crop_stage": "Vegetative", "count": 9, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Planthoppers sheltering in thick tillering hill centers.",
                "symptoms": "Lower leaf yellowing",
                "indicators": ["Hopperburn (yellowing and drying patches)"],
                "diagnosis": "Medium BPH infestation.",
                "guidance": "Alternate wetting and drying; conserve beneficial mirid bugs.",
                "days_ago": 5, "treatment_type": "cultural",
                "treatment_text": "Drained standing water for 4 days; allowed field surface to dry slightly",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Culasi",
        "lat": 11.4320, "lng": 122.0620,
        "barangays": ["Centro Poblacion", "Balac-balac", "Lipata", "Bitadton"],
        "farmer_name": "Neil Monmon", "farmer_email": "monmon7789al@gmail.com",
        "phone": "+63 917 111 0114",
        "scans": [
            {
                "pest": "brown_planthopper", "crop_stage": "Vegetative", "count": 15, "severity": "HIGH",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Rapid hopper multiplier observed near coastal paddy areas.",
                "symptoms": "Hopperburn patches, plant wilting",
                "indicators": ["Hopperburn (yellowing and drying patches)", "Plants wilting or lodging"],
                "diagnosis": "High BPH count; imminent risk of circular hopperburn patches.",
                "guidance": "Intermittent irrigation drainage; spot treat with buprofezin if unmanaged.",
                "days_ago": 14, "treatment_type": "cultural",
                "treatment_text": "Executed 5-day AWD field drainage and pruned bund weeds",
                "has_followup": True, "followup_count": 3
            },
            {
                "pest": "green_leafhopper", "crop_stage": "Vegetative", "count": 2, "severity": "LOW",
                "status": "pending", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Low leafhopper density on newly planted seedbeds.",
                "symptoms": "None",
                "indicators": [],
                "diagnosis": "",
                "guidance": "",
                "days_ago": 1, "treatment_type": None,
                "has_followup": False
            }
        ]
    },
    {
        "name": "Sebaste",
        "lat": 11.5920, "lng": 122.0920,
        "barangays": ["Poblacion", "Alegre", "Aras-asan", "Idio"],
        "farmer_name": "Gloria Alegre", "farmer_email": "gloria.sebaste@antique.gov.ph",
        "phone": "+63 917 111 0115",
        "scans": [
            {
                "pest": "rice_bug", "crop_stage": "Reproductive", "count": 7, "severity": "MEDIUM",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Adult bugs present on flowering heads across border rows.",
                "symptoms": "Brown speckled grain hulls",
                "indicators": ["Empty or unfilled grains", "Brown spots on grains"],
                "diagnosis": "Moderate rice bug feeding on developing milk grains.",
                "guidance": "Place decaying fish/meat attractant lures at 10-meter intervals.",
                "days_ago": 8, "treatment_type": "ecological",
                "treatment_text": "Installed decaying fish attractant traps and collected sluggish bugs at dawn",
                "has_followup": True, "followup_count": 2
            },
            {
                "pest": "rice_stem_borer", "crop_stage": "Vegetative", "count": 3, "severity": "LOW",
                "status": "validated", "method": "Trap Observation", "trap": "Pheromone Trap",
                "notes": "Pheromone trap caught few yellow stem borer moths.",
                "symptoms": "None",
                "indicators": [],
                "diagnosis": "Stem borer level is low.",
                "guidance": "Monitor weekly; conserve beneficial parasitoid wasps.",
                "days_ago": 3, "treatment_type": "biological",
                "treatment_text": "Protected native damselfly and spider populations",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Pandan",
        "lat": 11.7220, "lng": 122.0950,
        "barangays": ["Centro Sur", "Centro Norte", "Duyong", "Mag-aba"],
        "farmer_name": "Gregorio Duyong", "farmer_email": "gregorio.pandan@antique.gov.ph",
        "phone": "+63 917 111 0116",
        "scans": [
            {
                "pest": "green_leafhopper", "crop_stage": "Vegetative", "count": 5, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Leafhopper population building up along riverbank paddy plots.",
                "symptoms": "Slight stunting",
                "indicators": ["Stunted plants"],
                "diagnosis": "Moderate GLH count; potential tungro vector risk.",
                "guidance": "Rogue out suspicious yellow hills immediately; monitor trap counts.",
                "days_ago": 10, "treatment_type": "cultural",
                "treatment_text": "Uprooted and destroyed 8 suspicious yellow-orange hills; cleaned irrigation edges",
                "has_followup": True, "followup_count": 1
            },
            {
                "pest": "brown_planthopper", "crop_stage": "Reproductive", "count": 17, "severity": "HIGH",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Significant hopper congregation around lower stem base during booting.",
                "symptoms": "Hopperburn patches spreading",
                "indicators": ["Hopperburn (yellowing and drying patches)", "Honeydew or sooty mold at the plant base"],
                "diagnosis": "High BPH threat.",
                "guidance": "Drain water 4 days; spot spray buprofezin if population continues rising.",
                "days_ago": 6, "treatment_type": "chemical",
                "treatment_text": "Spot-treated affected patches with selective insect growth regulator per DA label",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Libertad",
        "lat": 11.7720, "lng": 121.9220,
        "barangays": ["San Roque", "Central", "Union", "Pajo"],
        "farmer_name": "Luisa Central", "farmer_email": "luisa.libertad@antique.gov.ph",
        "phone": "+63 917 111 0117",
        "scans": [
            {
                "pest": "rice_stem_borer", "crop_stage": "Vegetative", "count": 5, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Pheromone Trap",
                "notes": "Deadhearts observed in central seedbeds.",
                "symptoms": "Dead central tillers",
                "indicators": ["Deadhearts (dead central tiller)"],
                "diagnosis": "Moderate stem borer larval damage.",
                "guidance": "Deploy Trichogramma cards; hand destroy visible egg clusters.",
                "days_ago": 9, "treatment_type": "biological",
                "treatment_text": "Released 40 Trichogramma cards and inspected nursery for egg masses",
                "has_followup": True, "followup_count": 1
            },
            {
                "pest": "rice_bug", "crop_stage": "Ripening", "count": 3, "severity": "LOW",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Minimal bug count as harvest approaches.",
                "symptoms": "Minor grain pecking",
                "indicators": [],
                "diagnosis": "Low infestation; harvest within 10 days.",
                "guidance": "Prepare for harvest; no chemical interventions needed.",
                "days_ago": 4, "treatment_type": "cultural",
                "treatment_text": "Maintained clean field bunds and scheduled timely harvest",
                "has_followup": False
            }
        ]
    },
    {
        "name": "Caluya",
        "lat": 12.0120, "lng": 121.4250,
        "barangays": ["Poblacion", "Sibato", "Semirara", "Alegria"],
        "farmer_name": "Fernando Semirara", "farmer_email": "fernando.caluya@antique.gov.ph",
        "phone": "+63 917 111 0118",
        "scans": [
            {
                "pest": "brown_planthopper", "crop_stage": "Vegetative", "count": 10, "severity": "MEDIUM",
                "status": "validated", "method": "Trap Observation", "trap": "Sticky Trap",
                "notes": "Planthoppers active in island lowland rice paddies.",
                "symptoms": "Yellowing leaf sheaths",
                "indicators": ["Honeydew or sooty mold at the plant base"],
                "diagnosis": "Medium BPH population on island lowland rice fields.",
                "guidance": "Intermittent wetting and drying; split nitrogen fertilizer into 3 doses.",
                "days_ago": 11, "treatment_type": "cultural",
                "treatment_text": "Applied alternate wetting and drying for 4 days and split urea dose",
                "has_followup": True, "followup_count": 2
            },
            {
                "pest": "rice_bug", "crop_stage": "Reproductive", "count": 6, "severity": "MEDIUM",
                "status": "validated", "method": "Direct Field Observation", "trap": "Direct Count",
                "notes": "Bugs spotted on milky panicles near coastline dikes.",
                "symptoms": "Empty grains",
                "indicators": ["Empty or unfilled grains"],
                "diagnosis": "Moderate rice bug count at milk stage.",
                "guidance": "Install odorous bait traps; conduct early morning sweep netting.",
                "days_ago": 5, "treatment_type": "ecological",
                "treatment_text": "Deployed 6 snail bait traps on bamboo stakes and hand-netted adults",
                "has_followup": False
            }
        ]
    }
]

print(f"Total municipalities configured: {len(MUNICIPALITIES_DATA)}")

def build_sql():
    sql_lines = [
        "-- ==============================================================================",
        "-- 04_all_municipalities_data.sql",
        "-- Comprehensive Seed Data for all 18 Municipalities of Antique Province",
        "-- Pests: Brown Planthopper, Green Leafhopper, Rice Bug, Rice Stem Borer",
        "-- Covers: Users, Geotagged Scans, IPM Treatments, Follow-ups, Reviews & Alerts",
        "-- ==============================================================================",
        "",
        "-- -----------------------------------------------------------------------------",
        "-- 1. USERS FOR ALL MUNICIPALITIES (Run on rice_pest_db2)",
        "-- -----------------------------------------------------------------------------",
    ]
    
    # 1. Users SQL
    for m in MUNICIPALITIES_DATA:
        m_name = m["name"]
        f_name = m["farmer_name"]
        f_email = m["farmer_email"]
        f_brgy = m["barangays"][0]
        phone = m["phone"]
        sql_lines.append(f"""INSERT INTO users (email, password_hash, full_name, role, region, barangay, phone, is_verified, status, coverage_barangays, reviewed_by, reviewed_at, created_at)
VALUES ('{f_email}', '{PASSWORD_HASH}', '{f_name}', 'farmer', '{m_name}', '{f_brgy}', '{phone}', TRUE, 'approved', '', 'Neil Denise Tating Cabañero', CURRENT_TIMESTAMP - INTERVAL '30 days', CURRENT_TIMESTAMP - INTERVAL '45 days')
ON CONFLICT (email) DO UPDATE
SET full_name = EXCLUDED.full_name, region = EXCLUDED.region, barangay = EXCLUDED.barangay, status = 'approved', is_verified = TRUE;""")

    sql_lines.append("\n-- Regional Technicians")
    technicians = [
        ("tech.south@antique.gov.ph", "Marl Ellie Supat", "technician", "San Jose de Buenavista", "Casay, Poblacion, Guintas, Funda-Dalipe", "+63 917 222 0001"),
        ("tech.central@antique.gov.ph", "Arsenio Alcala", "technician", "Sibalom", "Bongbongan I, Maradiona, Aureliana, Ubos", "+63 917 222 0002"),
        ("tech.north@antique.gov.ph", "Lourdes Pajarillo", "technician", "Culasi", "Centro Ilawod, Guiamon, Binanu-an, Lipata", "+63 917 222 0003"),
        ("tech.pandan@antique.gov.ph", "Joaquin Dioso", "technician", "Pandan", "Centro Sur, Aras-asan, Union, Semirara", "+63 917 222 0004"),
    ]
    for email, name, role, region, cov, phone in technicians:
        sql_lines.append(f"""INSERT INTO users (email, password_hash, full_name, role, region, barangay, phone, is_verified, status, coverage_barangays, reviewed_by, reviewed_at, created_at)
VALUES ('{email}', '{PASSWORD_HASH}', '{name}', '{role}', '{region}', 'Poblacion', '{phone}', TRUE, 'approved', '{cov}', 'Neil Denise Tating Cabañero', CURRENT_TIMESTAMP - INTERVAL '60 days', CURRENT_TIMESTAMP - INTERVAL '90 days')
ON CONFLICT (email) DO UPDATE
SET full_name = EXCLUDED.full_name, region = EXCLUDED.region, status = 'approved', is_verified = TRUE, coverage_barangays = EXCLUDED.coverage_barangays;""")

    sql_lines.append("\n-- -----------------------------------------------------------------------------")
    sql_lines.append("-- 2. FIELD OBSERVATIONS ACROSS ALL MUNICIPALITIES (Run on rice_pest_geo)")
    sql_lines.append("-- -----------------------------------------------------------------------------\n")

    for m in MUNICIPALITIES_DATA:
        m_name = m["name"]
        lat = m["lat"]
        lng = m["lng"]
        f_email = m["farmer_email"]
        for s_idx, s in enumerate(m["scans"]):
            brgy = m["barangays"][s_idx % len(m["barangays"])]
            s_pest = s["pest"]
            s_stage = s["crop_stage"]
            s_count = s["count"]
            s_sev = s["severity"]
            s_status = s["status"]
            s_method = s["method"]
            s_trap = s["trap"]
            s_notes = s["notes"].replace("'", "''")
            s_symp = s["symptoms"].replace("'", "''")
            s_diag = s["diagnosis"].replace("'", "''")
            s_guid = s["guidance"].replace("'", "''")
            s_days = s["days_ago"]
            inds = ", ".join(f"'{i.replace("'", "''")}'" for i in s["indicators"])
            inds_arr = f"ARRAY[{inds}]::text[]" if inds else "'{}'::text[]"
            
            density = s_count * 4.0
            img_file = f"scan_{m_name.lower().replace(' ', '_')}_{s_idx+1}.jpg"
            val_by = "'Neil Denise Tating Cabañero'" if s_status == 'validated' else 'NULL'
            val_at = f"CURRENT_TIMESTAMP - INTERVAL '{s_days - 1} days'" if s_status == 'validated' else 'NULL'
            conf_pest = f"'{s_pest}'" if s_status == 'validated' else 'NULL'
            conf_count = str(s_count) if s_status == 'validated' else 'NULL'
            ret_reason = "'Photo too blurry; please retake with steady lighting.'" if s_status == 'returned' else "''"
            esc_reason = "'Suspected severe tungro vector aggregation; required regional verification.'" if s_status == 'escalated' else "''"

            sql_lines.append(f"""-- Observation in {m_name}, Brgy {brgy} ({s_pest})
INSERT INTO scans (
    user_email, image_filename, notes, geom, created_at,
    total_count, dominant_class, density, severity, crop_phase,
    symptoms, trap_type, monitoring_method, target_pest,
    diagnosis, guidance, validation_status, corrected_count,
    validated_by, validated_at, report_type, municipality,
    barangay, submitted_by_role, ai_status, ai_pest,
    ai_confidence, ai_count, ai_countable, confirmed_pest,
    confirmed_count, countable, infestation_level, damage_indicators,
    return_reason, escalation_reason
)
SELECT
    '{f_email}', '{img_file}', '{s_notes}', ST_SetSRID(ST_MakePoint({lng + s_idx*0.005}, {lat + s_idx*0.004}), 4326),
    CURRENT_TIMESTAMP - INTERVAL '{s_days} days', {s_count}, '{s_pest}', {density}, '{s_sev}', '{s_stage}',
    '{s_symp}', '{s_trap}', '{s_method}', '{s_pest.replace('_', ' ').title()}',
    '{s_diag}', '{s_guid}', '{s_status}', {conf_count},
    {val_by}, {val_at}, 'pest', '{m_name}',
    '{brgy}', 'farmer', 'done', '{s_pest}',
    0.91, {s_count}, TRUE, {conf_pest},
    {conf_count}, TRUE, '{s_sev}', {inds_arr},
    {ret_reason}, {esc_reason}
WHERE NOT EXISTS (SELECT 1 FROM scans WHERE image_filename = '{img_file}');""")

    return "\n".join(sql_lines)

# Write the SQL file
sql_content = build_sql()
with open("SQL/04_all_municipalities_data.sql", "w", encoding="utf-8") as f:
    f.write(sql_content)
print(f"Generated SQL/04_all_municipalities_data.sql (bytes: {len(sql_content)})")

# Execute in PostgreSQL
try:
    print("Executing on rice_pest_db2...")
    with psycopg.connect("postgresql://user:7789@localhost:5432/rice_pest_db2") as conn:
        with conn.cursor() as cur:
            for m in MUNICIPALITIES_DATA:
                m_name = m["name"]
                f_name = m["farmer_name"]
                f_email = m["farmer_email"]
                f_brgy = m["barangays"][0]
                phone = m["phone"]
                cur.execute("""
                    INSERT INTO users (email, password_hash, full_name, role, region, barangay, phone, is_verified, status, coverage_barangays, reviewed_by, reviewed_at, created_at)
                    VALUES (%s, %s, %s, 'farmer', %s, %s, %s, TRUE, 'approved', '', 'Neil Denise Tating Cabañero', CURRENT_TIMESTAMP - INTERVAL '30 days', CURRENT_TIMESTAMP - INTERVAL '45 days')
                    ON CONFLICT (email) DO UPDATE
                    SET full_name = EXCLUDED.full_name, region = EXCLUDED.region, barangay = EXCLUDED.barangay, status = 'approved', is_verified = TRUE
                """, (f_email, PASSWORD_HASH, f_name, m_name, f_brgy, phone))

            technicians = [
                ("tech.south@antique.gov.ph", "Marl Ellie Supat", "technician", "San Jose de Buenavista", "Casay, Poblacion, Guintas, Funda-Dalipe", "+63 917 222 0001"),
                ("tech.central@antique.gov.ph", "Arsenio Alcala", "technician", "Sibalom", "Bongbongan I, Maradiona, Aureliana, Ubos", "+63 917 222 0002"),
                ("tech.north@antique.gov.ph", "Lourdes Pajarillo", "technician", "Culasi", "Centro Ilawod, Guiamon, Binanu-an, Lipata", "+63 917 222 0003"),
                ("tech.pandan@antique.gov.ph", "Joaquin Dioso", "technician", "Pandan", "Centro Sur, Aras-asan, Union, Semirara", "+63 917 222 0004"),
            ]
            for email, name, role, region, cov, phone in technicians:
                cur.execute("""
                    INSERT INTO users (email, password_hash, full_name, role, region, barangay, phone, is_verified, status, coverage_barangays, reviewed_by, reviewed_at, created_at)
                    VALUES (%s, %s, %s, %s, %s, 'Poblacion', %s, TRUE, 'approved', %s, 'Neil Denise Tating Cabañero', CURRENT_TIMESTAMP - INTERVAL '60 days', CURRENT_TIMESTAMP - INTERVAL '90 days')
                    ON CONFLICT (email) DO UPDATE
                    SET full_name = EXCLUDED.full_name, region = EXCLUDED.region, status = 'approved', is_verified = TRUE, coverage_barangays = EXCLUDED.coverage_barangays
                """, (email, PASSWORD_HASH, name, role, region, phone, cov))
        conn.commit()
    print("Users successfully synced to rice_pest_db2!")
except Exception as e:
    print(f"Error on rice_pest_db2: {e}")

try:
    print("Executing on rice_pest_geo...")
    with psycopg.connect("postgresql://user:7789@localhost:5432/rice_pest_geo") as conn:
        with conn.cursor() as cur:
            for m in MUNICIPALITIES_DATA:
                m_name = m["name"]
                lat = m["lat"]
                lng = m["lng"]
                f_email = m["farmer_email"]
                for s_idx, s in enumerate(m["scans"]):
                    brgy = m["barangays"][s_idx % len(m["barangays"])]
                    s_pest = s["pest"]
                    s_stage = s["crop_stage"]
                    s_count = s["count"]
                    s_sev = s["severity"]
                    s_status = s["status"]
                    s_method = s["method"]
                    s_trap = s["trap"]
                    s_notes = s["notes"]
                    s_symp = s["symptoms"]
                    s_diag = s["diagnosis"]
                    s_guid = s["guidance"]
                    s_days = s["days_ago"]
                    inds = s["indicators"]
                    
                    density = s_count * 4.0
                    img_file = f"scan_{m_name.lower().replace(' ', '_')}_{s_idx+1}.jpg"
                    val_by = "Neil Denise Tating Cabañero" if s_status == 'validated' else None
                    val_at = datetime.now() - timedelta(days=s_days - 1) if s_status == 'validated' else None
                    conf_pest = s_pest if s_status == 'validated' else None
                    conf_count = s_count if s_status == 'validated' else None
                    ret_reason = "Photo too blurry; please retake with steady lighting." if s_status == 'returned' else ""
                    esc_reason = "Suspected severe tungro vector aggregation; required regional verification." if s_status == 'escalated' else ""

                    # Check if scan exists
                    cur.execute("SELECT id FROM scans WHERE image_filename = %s", (img_file,))
                    row = cur.fetchone()
                    if not row:
                        cur.execute("""
                            INSERT INTO scans (
                                user_email, image_filename, notes, geom, created_at,
                                total_count, dominant_class, density, severity, crop_phase,
                                symptoms, trap_type, monitoring_method, target_pest,
                                diagnosis, guidance, validation_status, corrected_count,
                                validated_by, validated_at, report_type, municipality,
                                barangay, submitted_by_role, ai_status, ai_pest,
                                ai_confidence, ai_count, ai_countable, confirmed_pest,
                                confirmed_count, countable, infestation_level, damage_indicators,
                                return_reason, escalation_reason
                            ) VALUES (
                                %s, %s, %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326),
                                CURRENT_TIMESTAMP - (%s * INTERVAL '1 day'), %s, %s, %s, %s, %s,
                                %s, %s, %s, %s,
                                %s, %s, %s, %s,
                                %s, %s, 'pest', %s,
                                %s, 'farmer', 'done', %s,
                                0.91, %s, TRUE, %s,
                                %s, TRUE, %s, %s,
                                %s, %s
                            ) RETURNING id
                        """, (
                            f_email, img_file, s_notes, lng + s_idx*0.005, lat + s_idx*0.004,
                            s_days, s_count, s_pest, density, s_sev, s_stage,
                            s_symp, s_trap, s_method, s_pest.replace('_', ' ').title(),
                            s_diag, s_guid, s_status, conf_count,
                            val_by, val_at, m_name,
                            brgy, s_pest, s_count, conf_pest,
                            conf_count, s_sev, inds,
                            ret_reason, esc_reason
                        ))
                        scan_id = cur.fetchone()[0]
                    else:
                        scan_id = row[0]

                    # If treatment applies
                    if s["treatment_type"] and s_status == 'validated':
                        # Find matching library_id
                        cur.execute("SELECT id FROM treatment_library WHERE pest = %s AND option_type = %s LIMIT 1", (s_pest, s["treatment_type"]))
                        lib_row = cur.fetchone()
                        lib_id = lib_row[0] if lib_row else None

                        cur.execute("SELECT id FROM treatments WHERE scan_id = %s", (scan_id,))
                        t_row = cur.fetchone()
                        if not t_row:
                            cur.execute("""
                                INSERT INTO treatments (
                                    scan_id, submitted_by, treatment, applied_at,
                                    pre_count, created_at, option_type, follow_up_due, library_id
                                ) VALUES (
                                    %s, %s, %s, CURRENT_TIMESTAMP - (%s * INTERVAL '1 day'),
                                    %s, CURRENT_TIMESTAMP - (%s * INTERVAL '1 day'), %s, CURRENT_DATE + INTERVAL '5 days', %s
                                ) RETURNING id
                            """, (
                                scan_id, f_email, s["treatment_text"], s_days - 2,
                                s_count, s_days - 2, s["treatment_type"], lib_id
                            ))
                            treatment_id = cur.fetchone()[0]
                        else:
                            treatment_id = t_row[0]

                        # If has followup scan
                        if s.get("has_followup"):
                            fu_file = f"followup_{m_name.lower().replace(' ', '_')}_{s_idx+1}.jpg"
                            cur.execute("SELECT id FROM scans WHERE image_filename = %s", (fu_file,))
                            if not cur.fetchone():
                                fu_count = s["followup_count"]
                                fu_sev = "LOW" if fu_count < 5 else "MEDIUM"
                                cur.execute("""
                                    INSERT INTO scans (
                                        user_email, image_filename, notes, geom, created_at,
                                        total_count, dominant_class, density, severity, crop_phase,
                                        symptoms, trap_type, monitoring_method, target_pest,
                                        diagnosis, guidance, validation_status, corrected_count,
                                        validated_by, validated_at, report_type, municipality,
                                        barangay, submitted_by_role, ai_status, ai_pest,
                                        ai_confidence, ai_count, ai_countable, confirmed_pest,
                                        confirmed_count, countable, infestation_level, damage_indicators,
                                        follow_up_of
                                    ) VALUES (
                                        %s, %s, %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326),
                                        CURRENT_TIMESTAMP - (%s * INTERVAL '1 day'), %s, %s, %s, %s, %s,
                                        'Post-treatment verification check; population reduced significantly', %s, %s, %s,
                                        'Effective pest suppression verified following intervention', 'Maintain weekly trap inspections', 'validated', %s,
                                        'Neil Denise Tating Cabañero', CURRENT_TIMESTAMP - (%s * INTERVAL '1 day'), 'pest', %s,
                                        %s, 'farmer', 'done', %s,
                                        0.94, %s, TRUE, %s,
                                        %s, TRUE, %s, '{}',
                                        %s
                                    )
                                """, (
                                    f_email, fu_file, f"Follow-up observation after {s['treatment_type']} treatment.", lng + s_idx*0.005 + 0.001, lat + s_idx*0.004 + 0.001,
                                    max(1, s_days - 6), fu_count, s_pest, fu_count * 4.0, fu_sev, s_stage,
                                    s_trap, s_method, s_pest.replace('_', ' ').title(),
                                    fu_count, max(1, s_days - 7), m_name,
                                    brgy, s_pest, fu_count, s_pest,
                                    fu_count, fu_sev, treatment_id
                                ))

                    # Scan review
                    if s_status in ('validated', 'escalated', 'returned'):
                        cur.execute("SELECT id FROM scan_reviews WHERE scan_id = %s", (scan_id,))
                        if not cur.fetchone():
                            cur.execute("""
                                INSERT INTO scan_reviews (
                                    scan_id, reviewer, reviewer_role, action, corrected_count,
                                    diagnosis, guidance, library_id, created_at, pest,
                                    countable, level, indicators
                                ) VALUES (
                                    %s, 'Neil Denise Tating Cabañero', 'technician', %s, %s,
                                    %s, %s, %s, CURRENT_TIMESTAMP - (%s * INTERVAL '1 day'), %s,
                                    TRUE, %s, %s
                                )
                            """, (
                                scan_id, s_status, conf_count,
                                s_diag, s_guid, None, s_days - 1, s_pest,
                                s_sev, inds
                            ))

                    # Notification
                    cur.execute("SELECT id FROM notifications WHERE scan_id = %s", (scan_id,))
                    if not cur.fetchone():
                        n_title = f"Scan Status: {s_status.capitalize()}"
                        n_body = f"Your field observation in {m_name} ({brgy}) has been {s_status} by municipal technician."
                        cur.execute("""
                            INSERT INTO notifications (
                                user_email, scan_id, kind, title, body, created_at
                            ) VALUES (
                                %s, %s, %s, %s, %s, CURRENT_TIMESTAMP - (%s * INTERVAL '1 day')
                            )
                        """, (
                            f_email, scan_id, s_status, n_title, n_body, s_days - 1
                        ))

        conn.commit()
    print("Scans, treatments, reviews, and notifications successfully synced to rice_pest_geo!")
except Exception as e:
    print(f"Error on rice_pest_geo: {e}")

