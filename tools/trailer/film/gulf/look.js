// 海湾战争版的光照：夜里（月光、夜视仪）、天亮 / 黄昏（太阳贴着地平线）、白天（沙漠的强光、沙尘的雾）
import * as THREE from 'three';
import { DEG, lerp } from '../lib.js';

// 方位角（度，0 = 北 −Z，90 = 东 +X）、高度角（度）→ 方向
export function dirAzEl(az, el) {
  const a = az * DEG, e = el * DEG;
  return new THREE.Vector3(Math.sin(a) * Math.cos(e), Math.sin(e), -Math.cos(a) * Math.cos(e)).normalize();
}
// 白天：sunEl 太阳高度角（度）；warm 0～1（越低越暖）；dust 沙尘大（雾浓、发黄）
export function day(o = {}) {
  const el = o.el ?? 32, az = o.az ?? 250;
  const sun = dirAzEl(az, el);
  const warm = o.warm ?? Math.max(0, 1 - el / 22);
  const dust = o.dust ?? 0.3;
  const haze = new THREE.Color().setRGB(lerp(0.62, 0.78, warm) * (0.9 + dust * 0.2), lerp(0.6, 0.55, warm), lerp(0.56, 0.4, warm) * (1 - dust * 0.15));
  const sunC = new THREE.Color().setRGB(1, lerp(0.95, 0.72, warm), lerp(0.86, 0.48, warm));
  const bright = Math.min(1, Math.sin(Math.max(el, 1) * DEG) * 2.6);
  return {
    day: 1, dawn: warm, sunDir: sun, moonDir: sun, moonVis: 0, moonI: (o.sunI ?? 7.5) * (0.45 + 0.55 * bright), moonC: sunC.getHex(),
    hemiI: o.hemiI ?? lerp(1.35, 2.2, bright), hemiSky: new THREE.Color().setRGB(0.42, 0.52, 0.72).lerp(haze, 0.35).getHex(), hemiGround: new THREE.Color(0.5, 0.39, 0.26).getHex(),
    fogColor: haze.clone(), haze: haze.clone(), fogDensity: o.fog ?? (0.000034 + dust * 0.00005),
    exposure: (o.exposure ?? 0.55) * 0.86, bloom: o.bloom ?? 0.55,   // ×0.86：写实地表（gulf/real.js）比原来的旧贴图亮、还多了天光
    bloomTh: o.bloomTh ?? 1.6, sat: o.sat ?? 1.0, contrast: o.contrast ?? 1.05,   // 这一行原来被上一行的注释吞了（写实化那次），白天镜头泛光阈值掉到 1.1、整片发灰发雾
    heat: o.heat ?? 0.6, grain: o.grain ?? 0.008, lift: 0.006, tint: o.tint ?? 0.6, cloud: o.cloud ?? 0.35, stars: 0,
    sky: o.sky ?? 'day', skyLum: o.skyLum ?? 0.42, skyHaze: o.skyHaze ?? 0.62,   // 真实天空（gulf/real.js）：哪张 HDRI、平均亮度、地平线的沙尘霾
    fxAmb: new THREE.Color().setRGB(0.2, 0.185, 0.16).multiplyScalar(0.45 + 0.55 * bright).lerp(new THREE.Color(0.2, 0.13, 0.08), warm * 0.4),
  };
}
// 天亮 / 黄昏：太阳贴着地平线（el 2～8 度），天发橙红，地上长长的影子
export function dusk(o = {}) {
  const P = day({ el: o.el ?? 4, az: o.az ?? 260, warm: 1, dust: o.dust ?? 0.45, sunI: o.sunI ?? 6.5, exposure: o.exposure ?? 0.78, heat: o.heat ?? 0.2, fog: o.fog });
  P.hemiI = o.hemiI ?? 1.05;
  P.hemiSky = new THREE.Color(0.38, 0.36, 0.48).getHex();
  P.bloom = o.bloom ?? 0.8; P.bloomTh = 1.3;
  P.sky = o.sky ?? 'dusk'; P.skyLum = o.skyLum ?? 0.2; P.skyHaze = o.skyHaze ?? 0.5;
  return P;
}
// 夜里：月光（偏冷、暗），沙漠的夜空很清
export function night(o = {}) {
  const moon = dirAzEl(o.az ?? 140, o.el ?? 38);
  return {
    day: 0, dawn: 0, moonDir: moon, sunDir: dirAzEl(20, -30), moonVis: 1, moonI: (o.moonI ?? 2.6) * 0.72, moonC: 0x9fb4da,
    hemiI: o.hemiI ?? 0.55, hemiSky: 0x2b3b5e, hemiGround: 0x15110c, cloud: o.cloud ?? 0.12,
    fogColor: new THREE.Color(0.035, 0.045, 0.07), fogDensity: o.fog ?? 0.00007, exposure: (o.exposure ?? 1.25) * 0.85, bloom: o.bloom ?? 1.15, heat: 0, grain: o.grain ?? 0.016,
    contrast: 1.1, sat: 0.85,
    sky: o.sky ?? 'night', skyLum: o.skyLum ?? 0.012, skyHaze: o.skyHaze ?? 0.75,
  };
}
