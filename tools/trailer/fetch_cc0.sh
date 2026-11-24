#!/bin/bash
# 宣传片（海湾战争版）用的 CC0 素材：Poly Haven（https://polyhaven.com，全部 CC0 1.0）的地表贴图、天空 HDRI，下载到数据目录 assets/ph/
#   用法（仓库根目录）：bash tools/trailer/fetch_cc0.sh <数据目录>
#   地表：sandy_gravel_02（沙砾平原）、gravelly_sand（砾漠）、dry_ground_01（干河床、盐碱滩边上龟裂的地）、aerial_beach_03（踩乱的软沙）、
#         rock_06、worn_rock_natural_01（方山、断崖的岩面）——各取 2K 的底色、法线（OpenGL）、arm（AO / 粗糙度 / 金属度）
#   天空：qwantani 一组纯天空 HDRI（同一个地方、同一天的不同时刻：日出、上午、下午、黄昏、夜里）2K
set -e
D=${1:?用法：bash tools/trailer/fetch_cc0.sh <数据目录>}
O="$D/assets/ph"
mkdir -p "$O"
TEX="sandy_gravel_02 gravelly_sand dry_ground_01 aerial_beach_03 rock_06 worn_rock_natural_01"
HDR="qwantani_sunrise_puresky qwantani_mid_morning_puresky qwantani_afternoon_puresky qwantani_dusk_1_puresky qwantani_night_puresky"
get() { [ -s "$2" ] || { curl -sfL --retry 4 --max-time 300 "$1" -o "$2.part" && mv -f "$2.part" "$2"; }; }
for a in $TEX $HDR; do
  [ -s "$O/$a.json" ] || curl -sfL --retry 4 --max-time 60 "https://api.polyhaven.com/files/$a" -o "$O/$a.json"
done
for a in $TEX; do
  for m in Diffuse nor_gl arm; do
    u=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]['2k']['jpg']['url'])" "$O/$a.json" "$m")
    get "$u" "$O/${a}_${m}_2k.jpg"
  done
done
for a in $HDR; do
  u=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['hdri']['2k']['hdr']['url'])" "$O/$a.json")
  get "$u" "$O/${a}_2k.hdr"
done
ls -la "$O" | grep -v json
