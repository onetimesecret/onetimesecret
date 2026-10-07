// scripts/globes/presets.mjs
//
// One entry per committed globe icon. build.mjs renders each with makeGlobe()
// and writes src/shared/components/icons/sprites/OtsSprites.vue.
// Symbol ids are `ots-<name>`, i.e. <OIcon collection="ots" name="<name>" />.
// Options are documented at the top of make-globe.mjs.

const EU = [
  'Austria', 'Belgium', 'Bulgaria', 'Croatia', 'Cyprus', 'Czechia', 'Denmark', 'Estonia', 'Finland',
  'France', 'Germany', 'Greece', 'Hungary', 'Ireland', 'Italy', 'Latvia', 'Lithuania', 'Luxembourg',
  'Malta', 'Netherlands', 'Poland', 'Portugal', 'Romania', 'Slovakia', 'Slovenia', 'Spain', 'Sweden',
];

const large = { smooth: 15, minArea: 1200 };

export default {
  'earth-canada': { ...large, center: [-96, 59], zoom: 2, focus: ['Canada'] },
  'earth-united-states': { ...large, center: [-98, 39], zoom: 2, focus: ['United States of America'] },
  'earth-mexico': { center: [-101, 23], zoom: 3.2, smooth: 11, grow: 1, minArea: 900, focus: ['Mexico'] },
  'earth-brazil': { ...large, center: [-53, -13], zoom: 2, focus: ['Brazil'] },
  'earth-european-union': { center: [12, 50], zoom: 3, smooth: 11, minArea: 600, focus: EU },
  'earth-united-kingdom': { center: [-3, 54.5], zoom: 6, smooth: 9, grow: 1.5, minArea: 1000, focus: ['United Kingdom'] },
  'earth-australia': { ...large, center: [136, -24], zoom: 2, focus: ['Australia'] },
  'earth-new-zealand': { center: [173, -41.5], zoom: 7.5, smooth: 8, open: 2, grow: 3.5 },
  'earth-japan': { center: [137.5, 37.5], zoom: 4.5, smooth: 8, open: 2.5, grow: 2, minArea: 600, focus: ['Japan'] },
  'earth-singapore': {
    center: [103.8, 1.35], zoom: 6, smooth: 10, grow: 1.5, minArea: 1000, focus: ['Singapore'], pin: 36, pinGap: 10,
  },
};
