import { ACTION_BG, ACTION_FG, BORDER, INK, MUTED, SOFT, SUCCESS, SURFACE } from './Theme';

// Shared controls. Dynamic values are passed as functions so that state read inside them keeps
// the caller's UI reactive (a value parameter would be captured once and never refresh).

@Builder
export function actionButton(label: () => string, id: string, action: () => void,
  enabled: () => boolean = () => true, primary: boolean = true) {
  Button({ type: ButtonType.Normal }) {
    Text(label()).fontSize(15).fontWeight(FontWeight.Medium).fontColor(primary ? ACTION_FG : INK)
      .textAlign(TextAlign.Center).width('100%')
  }.id(id).width('100%').constraintSize({ minHeight: 48 }).padding(12).borderRadius(12)
    .backgroundColor(primary ? ACTION_BG : SOFT).enabled(enabled()).opacity(enabled() ? 1 : 0.5)
    .accessibilityText(label()).onClick(action)
}

@Builder
export function iconButton(icon: Resource, label: () => string, id: string, action: () => void) {
  Button({ type: ButtonType.Normal }) {
    SymbolGlyph(icon).fontSize(22).maxFontScale(1).fontColor([INK]).accessibilityLevel('no')
  }.id(id).width(48).height(48).borderRadius(12).backgroundColor(Color.Transparent)
    .accessibilityText(label()).onClick(action)
}

@Builder
export function divider() { Divider().color(BORDER).strokeWidth(0.5) }

@Builder
export function sectionTitle(title: () => string) {
  Text(title()).fontSize(13).fontWeight(FontWeight.Medium).fontColor(MUTED).width('100%')
    .margin({ top: 8, bottom: 4 })
}

@Builder
export function rowLink(icon: Resource, title: () => string, detail: () => string, id: string, action: () => void) {
  Button({ type: ButtonType.Normal }) {
    Row({ space: 14 }) {
      SymbolGlyph(icon).fontSize(23).maxFontScale(1).fontColor([INK]).accessibilityLevel('no')
      Column({ space: 4 }) {
        Text(title()).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
        if (detail().length > 0) { Text(detail()).fontSize(13).fontColor(MUTED).width('100%') }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).maxFontScale(1).fontColor([MUTED])
        .accessibilityLevel('no')
    }.width('100%').padding({ top: 16, bottom: 16 })
  }.id(id).width('100%').constraintSize({ minHeight: 64 }).backgroundColor(Color.Transparent)
    .borderRadius(8).accessibilityText(title() + '. ' + detail()).onClick(action)
}

@Builder
export function metric(value: () => number, label: () => string) {
  Column({ space: 5 }) {
    Text(String(value())).fontSize(26).fontWeight(FontWeight.Medium).fontColor(INK)
    Text(label()).fontSize(12).fontColor(MUTED).textAlign(TextAlign.Center).width('100%')
  }.layoutWeight(1).padding({ top: 16, bottom: 16 })
}

@Builder
export function sourceLink(url: string, label: () => string) {
  Hyperlink(url, label()).color(INK).width('100%').constraintSize({ minHeight: 48 })
    .padding({ top: 12, bottom: 12 })
}

/** Full-width list choice with a check mark (Settings). */
@Builder
export function settingsChoice(label: () => string, id: string, selected: () => boolean, action: () => void,
  busy: () => boolean) {
  Button({ type: ButtonType.Normal }) {
    Row({ space: 16 }) {
      Text(label()).fontSize(16).fontColor(INK).layoutWeight(1)
      SymbolGlyph(selected() ? $r('sys.symbol.checkmark_circle_fill_1') : $r('sys.symbol.circle'))
        .fontSize(22).maxFontScale(1).fontColor([selected() ? SUCCESS : MUTED]).accessibilityLevel('no')
    }.width('100%').padding(16)
  }.id(id).width('100%').constraintSize({ minHeight: 54 }).backgroundColor(SURFACE).borderRadius(0)
    .accessibilityText(label()).accessibilitySelected(selected()).enabled(!busy()).onClick(action)
}

/** Labelled on/off switch row (Settings). */
@Builder
export function settingsToggle(label: () => string, id: string, isOn: () => boolean, change: (enabled: boolean) => void,
  busy: () => boolean) {
  Row({ space: 16 }) {
    Text(label()).fontSize(16).fontColor(INK).layoutWeight(1)
    Toggle({ type: ToggleType.Switch, isOn: isOn() }).id(id).selectedColor(SUCCESS)
      .enabled(!busy()).accessibilityText(label()).onChange(change)
  }.width('100%').padding(16).constraintSize({ minHeight: 54 }).backgroundColor(SURFACE)
}

/** Segmented choice button (issuer console). */
@Builder
export function choiceButton(label: () => string, id: string, selected: () => boolean, action: () => void,
  busy: () => boolean) {
  Button({ type: ButtonType.Normal }) {
    Text(label()).fontSize(14).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center).width('100%')
      .fontColor(selected() ? ACTION_FG : INK)
  }.id(id).layoutWeight(1).constraintSize({ minHeight: 48 }).padding(10).borderRadius(10)
    .backgroundColor(selected() ? ACTION_BG : SOFT).accessibilityText(label()).accessibilitySelected(selected())
    .enabled(!busy()).onClick(action)
}
