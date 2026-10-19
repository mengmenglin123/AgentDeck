import { argbFromHex, Hct, SchemeTonalSpot, MaterialDynamicColors, hexFromArgb } from "@material/material-color-utilities";
const presets = { brand: "#5E6AD2", forest: "#2E7D5B", sunset: "#C2652A", ocean: "#1E6FB8", graphite: "#5A6270" };
const roles = ["primary","onPrimary","primaryContainer","onPrimaryContainer","inversePrimary","secondary","onSecondary","secondaryContainer","onSecondaryContainer","tertiary","onTertiary","tertiaryContainer","onTertiaryContainer","background","onBackground","surface","onSurface","surfaceVariant","onSurfaceVariant","surfaceTint","inverseSurface","inverseOnSurface","error","onError","errorContainer","onErrorContainer","outline","outlineVariant","scrim","surfaceBright","surfaceContainer","surfaceContainerHigh","surfaceContainerHighest","surfaceContainerLow","surfaceContainerLowest","surfaceDim"];
const map = {surfaceTint:"surfaceTint", onBackground:"onBackground"};
let out = "package com.huanmeng.huanhermes.ui.theme\n\nimport androidx.compose.material3.ColorScheme\nimport androidx.compose.material3.darkColorScheme\nimport androidx.compose.material3.lightColorScheme\nimport androidx.compose.ui.graphics.Color\n\n// Generated with @material/material-color-utilities (SchemeTonalSpot) from each preset's seed. Do not edit by hand.\ninternal object Palettes {\n";
for (const [id, hex] of Object.entries(presets)) {
  for (const dark of [false, true]) {
    for (const contrast of [0, 0.5]) {
      const s = new SchemeTonalSpot(Hct.fromInt(argbFromHex(hex)), dark, contrast);
      const name = `${id}${dark ? "Dark" : "Light"}${contrast ? "Hc" : ""}`;
      out += `    val ${name}: ColorScheme = ${dark ? "darkColorScheme" : "lightColorScheme"}(\n`;
      for (const r of roles) {
        const dc = MaterialDynamicColors[r];
        if (!dc) { console.error("missing", r); continue; }
        out += `        ${r} = Color(0xFF${hexFromArgb(dc.getArgb(s)).slice(1).toUpperCase()}),\n`;
      }
      out += "    )\n";
    }
  }
}
out += "\n    fun scheme(id: String, dark: Boolean, highContrast: Boolean): ColorScheme = when (id) {\n";
for (const id of Object.keys(presets)) out += `        "${id}" -> if (dark) { if (highContrast) ${id}DarkHc else ${id}Dark } else { if (highContrast) ${id}LightHc else ${id}Light }\n`;
out += "        else -> if (dark) { if (highContrast) brandDarkHc else brandDark } else { if (highContrast) brandLightHc else brandLight }\n    }\n}\n";
import fs from "fs"; fs.writeFileSync("Palettes.kt", out);
