// All dashboard translations, merged from ./parts (one file per area so
// they can be reviewed separately). Later parts win on a duplicate key.
import activity from './parts/activity.js';
import analysis from './parts/analysis.js';
import common from './parts/common.js';
import field from './parts/field.js';
import records from './parts/records.js';
import reference from './parts/reference.js';
import server from './parts/server.js';
import update2026 from './parts/update2026.js';
import users from './parts/users.js';

export const TRANSLATIONS = {
  ...server,
  ...common,
  ...records,
  ...activity,
  ...analysis,
  ...reference,
  ...field,
  ...users,
  ...update2026,
};
