// SPDX-License-Identifier: Apache-2.0

/// One ALSA control, and what the app calls it. A card that lacks the control simply does not offer it.
class Mapping {
  const Mapping(
    this.id,
    this.group,
    this.label,
    this.alsaName, {
    this.invert = false,
  });
  final String id, group, label, alsaName;

  /// The ALSA switch means the opposite of the control ("mute" is the inverse of a playback switch).
  final bool invert;
}

/// The names are the in-tree ca0132 driver's own (kernel 7.2), listed from a live AE-5 Plus. Catalogue order is display order.
const alsaCatalog = <Mapping>[
  Mapping('volume.master', 'Output', 'Volume', 'Master Playback Volume'),
  Mapping(
    'volume.mute',
    'Output',
    'Mute',
    'Master Playback Switch',
    invert: true,
  ),
  Mapping('output.select', 'Output', 'Output', 'Output Select'),
  Mapping(
    'output.auto_detect',
    'Output',
    'Switch automatically when headphones are plugged in',
    'HP/Speaker Auto Detect Playback Switch',
  ),
  Mapping(
    'output.headphone_gain',
    'Output',
    'Headphone impedance',
    'AE-5: Headphone Gain',
  ),
  Mapping('output.dac_filter', 'Output', 'DAC filter', 'AE-5: Sound Filter'),
  Mapping(
    'speakers.layout',
    'Speakers',
    'Speaker layout',
    'Surround Channel Config',
  ),
  Mapping(
    'speakers.full_range_front',
    'Speakers',
    'Front speakers are full range',
    'Full-Range Front Speakers',
  ),
  Mapping(
    'speakers.full_range_rear',
    'Speakers',
    'Rear speakers are full range',
    'Full-Range Rear Speakers',
  ),
  Mapping(
    'speakers.bass_redirection',
    'Speakers',
    'Redirect bass to the subwoofer',
    'Bass Redirection',
  ),
  Mapping(
    'speakers.bass_crossover',
    'Speakers',
    'Bass redirection crossover',
    'Bass Redirection Crossover',
  ),
  Mapping('input.source', 'Input', 'Input', 'Input Source'),
  Mapping(
    'input.mic_boost',
    'Input',
    'Microphone boost',
    'Mic Boost Capture Switch',
  ),
  Mapping('input.volume', 'Input', 'Recording volume', 'Capture Volume'),
  Mapping(
    'input.mute',
    'Input',
    'Mute recording',
    'Capture Switch',
    invert: true,
  ),
  Mapping(
    'fx.enable',
    'Effects',
    'Sound effects',
    'Enable OutFX Playback Switch',
  ),
  Mapping('fx.surround', 'Effects', 'Surround', 'FX: Surround Playback Switch'),
  Mapping(
    'fx.surround_level',
    'Effects',
    'Surround level',
    'FX: Surround Playback Volume',
  ),
  Mapping(
    'fx.crystalizer',
    'Effects',
    'Crystalizer',
    'FX: Crystalizer Playback Switch',
  ),
  Mapping(
    'fx.crystalizer_level',
    'Effects',
    'Crystalizer level',
    'FX: Crystalizer Playback Volume',
  ),
  Mapping(
    'fx.dialog_plus',
    'Effects',
    'Dialog Plus',
    'FX: Dialog Plus Playback Switch',
  ),
  Mapping(
    'fx.dialog_plus_level',
    'Effects',
    'Dialog Plus level',
    'FX: Dialog Plus Playback Volume',
  ),
  Mapping(
    'fx.smart_volume',
    'Effects',
    'Smart Volume',
    'FX: Smart Volume Playback Switch',
  ),
  Mapping(
    'fx.smart_volume_level',
    'Effects',
    'Smart Volume level',
    'FX: Smart Volume Playback Volume',
  ),
  Mapping(
    'fx.smart_volume_mode',
    'Effects',
    'Smart Volume mode',
    'FX: Smart Volume Setting',
  ),
  Mapping('fx.xbass', 'Effects', 'X-Bass', 'FX: X-Bass Playback Switch'),
  Mapping(
    'fx.xbass_level',
    'Effects',
    'X-Bass level',
    'FX: X-Bass Playback Volume',
  ),
  Mapping(
    'fx.xbass_crossover',
    'Effects',
    'X-Bass crossover',
    'FX: X-Bass Crossover Playback Volume',
  ),
  Mapping(
    'eq.enable',
    'Equalizer',
    'Equalizer',
    'FX: Equalizer Playback Switch',
  ),
  Mapping('eq.preset', 'Equalizer', 'Preset', 'FX: Equalizer Preset Switch'),
  Mapping('eq.band0', 'Equalizer', '31 Hz', 'EQ Band0 Playback Volume'),
  Mapping('eq.band1', 'Equalizer', '62 Hz', 'EQ Band1 Playback Volume'),
  Mapping('eq.band2', 'Equalizer', '125 Hz', 'EQ Band2 Playback Volume'),
  Mapping('eq.band3', 'Equalizer', '250 Hz', 'EQ Band3 Playback Volume'),
  Mapping('eq.band4', 'Equalizer', '500 Hz', 'EQ Band4 Playback Volume'),
  Mapping('eq.band5', 'Equalizer', '1 kHz', 'EQ Band5 Playback Volume'),
  Mapping('eq.band6', 'Equalizer', '2 kHz', 'EQ Band6 Playback Volume'),
  Mapping('eq.band7', 'Equalizer', '4 kHz', 'EQ Band7 Playback Volume'),
  Mapping('eq.band8', 'Equalizer', '8 kHz', 'EQ Band8 Playback Volume'),
  Mapping('eq.band9', 'Equalizer', '16 kHz', 'EQ Band9 Playback Volume'),
  Mapping(
    'mic.fx_enable',
    'Microphone',
    'Microphone effects',
    'Enable InFX Capture Switch',
  ),
  Mapping(
    'mic.voice_focus',
    'Microphone',
    'Voice Focus',
    'FX: Voice Focus Capture Switch',
  ),
  Mapping(
    'mic.wedge_angle',
    'Microphone',
    'Voice Focus angle',
    'Wedge Angle Capture Volume',
  ),
  Mapping(
    'mic.noise_reduction',
    'Microphone',
    'Noise reduction',
    'FX: Noise Reduction Capture Switch',
  ),
  Mapping(
    'mic.smart_volume',
    'Microphone',
    'Smart Volume',
    'FX: Mic SVM Capture Switch',
  ),
  Mapping(
    'mic.smart_volume_level',
    'Microphone',
    'Smart Volume level',
    'SVM Level Capture Volume',
  ),
  Mapping('mic.voicefx', 'Microphone', 'VoiceFX', 'VoiceFX Capture Switch'),
];

const _models = <int, String>{
  0x0010: 'Sound Blaster Z',
  0x0013: 'Sound Blaster Recon3D',
  0x0018: 'Sound Blaster Recon3D',
  0x0023: 'Sound Blaster Z',
  0x0024: 'Sound Blaster Z',
  0x0025: 'Sound Blaster Zx',
  0x0027: 'Sound Blaster Z',
  0x0028: 'Sound Blaster ZSE',
  0x0033: 'Sound Blaster ZxR',
  0x003f: 'Sound Blaster ZxR (DB)',
  0x0051: 'Sound BlasterX AE-5',
  0x0061: 'Sound BlasterX AE-3',
  0x0071: 'Sound BlasterX AE-9',
  0x0072: 'Sound BlasterX AE-9 (DB)',
  0x0073: 'Sound BlasterX AE-9 PE',
  0x0074: 'Sound BlasterX AE-9 PE (DB)',
  0x0081: 'Sound BlasterX AE-7',
  0x0191: 'Sound BlasterX AE-5 Plus',
};

String modelName(int subsystemVendor, int subsystemDevice) =>
    (subsystemVendor == 0x1102 ? _models[subsystemDevice] : null) ??
    'Creative sound card';
