import { divider, sourceLink } from './Controls';
import { INK, MUTED } from './Theme';
import { UiCopy } from './UiCopy';

/** Short offline preparedness guide. */
@Component
export struct GuideScreen {
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  @Link guideExpanded: number;

  private t(key: string): string { return this.copy.text(key, this.language); }

  @Builder
  private guideItem(index: number, title: string, body: string) {
    Column({ space: 0 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Text('0' + (index + 1)).fontSize(13).fontColor(MUTED).width(26)
          Text(this.t(title)).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).layoutWeight(1)
          SymbolGlyph(this.guideExpanded === index ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
            .fontSize(18).maxFontScale(1).fontColor([MUTED]).accessibilityLevel('no')
        }.padding({ top: 18, bottom: 18 }).width('100%')
      }.id('guideItem' + index).width('100%').constraintSize({ minHeight: 60 }).backgroundColor(Color.Transparent)
        .borderRadius(6).accessibilityText(this.t(title)).accessibilityDescription(this.t(this.guideExpanded === index ? 'collapse' : 'expand'))
        .onClick(() => { this.guideExpanded = this.guideExpanded === index ? -1 : index; })
      if (this.guideExpanded === index) {
        Text(this.t(body)).fontSize(15).fontColor(INK).width('100%').padding({ left: 38, bottom: 20 })
      }
      divider()
    }.width('100%')
  }

  build() {
    Column({ space: 16 }) {
      Text(this.t('guide_intro')).fontSize(15).fontColor(MUTED).width('100%')
      Column() {
        this.guideItem(0, 'guide1_title', 'guide1_body')
        this.guideItem(1, 'guide2_title', 'guide2_body')
        this.guideItem(2, 'guide3_title', 'guide3_body')
        this.guideItem(3, 'guide4_title', 'guide4_body')
      }.width('100%')
      Text(this.t('guide_offline')).fontSize(12).fontColor(MUTED).width('100%')
      sourceLink('https://www.gov.pl/web/poradnikbezpieczenstwa', () => this.t('source_safety'))
      Text(this.t('external_links')).fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
