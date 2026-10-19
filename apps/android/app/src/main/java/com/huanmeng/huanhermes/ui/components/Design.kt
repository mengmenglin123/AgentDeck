package com.huanmeng.huanhermes.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Shared look: grouped rounded lists (big outer corners, small inner ones),
 * tinted icon badges, small colour tags. Every list-like screen uses these so
 * the app reads as one design.
 */
object Design {
    val outer = 22.dp
    val inner = 6.dp
    val gap = 2.dp
    val screenPadding = 16.dp
}

/** Shape for item [index] of [count] inside a grouped list. */
fun groupShape(index: Int, count: Int, outer: Dp = Design.outer, inner: Dp = Design.inner): Shape = when {
    count <= 1 -> RoundedCornerShape(outer)
    index == 0 -> RoundedCornerShape(outer, outer, inner, inner)
    index == count - 1 -> RoundedCornerShape(inner, inner, outer, outer)
    else -> RoundedCornerShape(inner)
}

/** A titled group; [items] are drawn as one rounded stack. */
@Composable
fun SettingsGroup(title: String?, modifier: Modifier = Modifier, items: List<@Composable (Shape) -> Unit>) {
    Column(modifier.fillMaxWidth().padding(horizontal = Design.screenPadding)) {
        if (title != null) Text(
            title, Modifier.padding(start = 12.dp, top = 18.dp, bottom = 8.dp),
            style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary,
        )
        Column(verticalArrangement = Arrangement.spacedBy(Design.gap)) {
            items.forEachIndexed { i, item -> item(groupShape(i, items.size)) }
        }
    }
}

/** Accent for an icon badge; cycles so neighbouring groups differ. */
enum class Tint { Primary, Secondary, Tertiary, Error, Neutral }

@Composable
fun tintColors(t: Tint): Pair<Color, Color> {
    val c = MaterialTheme.colorScheme
    return when (t) {
        Tint.Primary -> c.primaryContainer to c.onPrimaryContainer
        Tint.Secondary -> c.secondaryContainer to c.onSecondaryContainer
        Tint.Tertiary -> c.tertiaryContainer to c.onTertiaryContainer
        Tint.Error -> c.errorContainer to c.onErrorContainer
        Tint.Neutral -> c.surfaceContainerHighest to c.onSurfaceVariant
    }
}

@Composable
fun IconBadge(icon: ImageVector, tint: Tint = Tint.Primary, size: Dp = 40.dp) {
    val (bg, fg) = tintColors(tint)
    Box(Modifier.size(size).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(size * 0.5f), tint = fg)
    }
}

/** One row in a [SettingsGroup]: badge, title, optional subtitle, trailing slot. */
@Composable
fun PrefItem(
    title: String,
    shape: Shape,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    tint: Tint = Tint.Primary,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    below: (@Composable ColumnScope.() -> Unit)? = null,
) {
    Surface(
        modifier.fillMaxWidth().clip(shape).then(if (onClick != null) Modifier.clickable(enabled = enabled, onClick = onClick) else Modifier),
        shape = shape, color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (icon != null) { IconBadge(icon, tint); Spacer(Modifier.width(14.dp)) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(title, style = MaterialTheme.typography.titleSmall,
                        color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                    if (!subtitle.isNullOrEmpty()) Text(subtitle, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 3, overflow = TextOverflow.Ellipsis)
                }
                if (trailing != null) { Spacer(Modifier.width(8.dp)); Row(verticalAlignment = Alignment.CenterVertically, content = trailing) }
            }
            if (below != null) Column(Modifier.padding(top = 10.dp), content = below)
        }
    }
}

/** Small coloured label (状态、能力、数量). */
@Composable
fun Tag(text: String, tint: Tint = Tint.Primary, modifier: Modifier = Modifier) {
    val (bg, fg) = tintColors(tint)
    Text(
        text, modifier.clip(RoundedCornerShape(6.dp)).background(bg).padding(horizontal = 6.dp, vertical = 2.dp),
        style = MaterialTheme.typography.labelSmall, color = fg, maxLines = 1,
    )
}

/** Large rounded card used for list entries that carry their own actions. */
@Composable
fun SoftCard(modifier: Modifier = Modifier, shape: Shape = RoundedCornerShape(Design.outer), onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier.fillMaxWidth().clip(shape).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        shape = shape, color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) { Column(Modifier.padding(16.dp), content = content) }
}
