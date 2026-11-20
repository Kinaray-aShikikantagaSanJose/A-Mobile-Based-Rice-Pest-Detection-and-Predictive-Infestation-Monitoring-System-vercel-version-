import L from 'leaflet';

// Leaflet.heat is a classic plugin that extends the global `L`, so Leaflet
// has to be on `window` before the plugin module runs. Import Leaflet from
// this file (first) wherever the plugin is used.
window.L = L;

export default L;
