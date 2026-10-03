import { common } from '@kit.AbilityKit';
import { LocalStore } from '../model/LocalStore';
import { AlertViewModel } from '../viewmodel/AlertViewModel';
import { MapViewModel, SafePointViewModel } from '../viewmodel/MapViewModel';
import { RelayViewModel, RelayEvent, PeerViewModel } from '../viewmodel/RelayViewModel';
import { OfflineMap } from '../views/OfflineMap';

const INK: string = '#183E35';
const MUTED: string = '#65776C';
const LIME: string = '#D8F58A';
const PAPER: string = '#F4F6F0';

@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State mapRevision: number = 0;
  @State notice: string = '';
  private store: LocalStore = new LocalStore();
  @State alerts: AlertViewModel = new AlertViewModel(this.store);
  @State map: MapViewModel = new MapViewModel();
  @State relay: RelayViewModel = new RelayViewModel(this.alerts);
  private expiryTimer: number = -1;
  private pageScroll: Scroller = new Scroller();

  aboutToAppear(): void {
    this.initialize();
    this.expiryTimer = setInterval(() => { this.alerts.refreshExpiry(); }, 10000);
  }
  aboutToDisappear(): void {
    if (this.expiryTimer !== -1) { clearInterval(this.expiryTimer); }
    this.alerts.dispose();
    this.relay.stop();
  }
  async initialize(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.store.init(context);
      this.map.savedId = await this.store.read('saved_point');
      this.relay.setContext(context);
      await this.alerts.restore();
      await this.relay.probe();
    } catch (error) { this.notice = 'Local setup: ' + String(error); }
  }
  async loadDrill(): Promise<void> {
    try { await this.alerts.loadDrill(); }
    catch (error) { this.notice = 'Could not verify drill: ' + String(error); }
  }
  selectPoint(id: string): void { this.map.select(id); this.mapRevision++; }
  selectTab(index: number): void {
    this.pageScroll.scrollTo({ xOffset: 0, yOffset: 0 });
    this.tab = index;
    this.notice = '';
  }
  async savePoint(): Promise<void> {
    this.map.savedId = this.map.selectedId;
    try { await this.store.write('saved_point', this.map.savedId); this.notice = 'Point saved on this phone.'; }
    catch (error) { this.notice = 'Could not save: ' + String(error); }
  }

  @Builder
  header() {
    Row({ space: 9 }) {
      Text('S').fontSize(21).fontWeight(FontWeight.Bold).fontColor(LIME)
        .width(34).height(34).textAlign(TextAlign.Center).backgroundColor(INK).borderRadius(11)
      Text('safemesh').fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).letterSpacing(-0.8)
      Blank()
      Text('●  OFFLINE READY').fontSize(9).fontWeight(FontWeight.Bold).fontColor(INK)
        .backgroundColor('#E3EDD8').padding({ left: 10, right: 10, top: 8, bottom: 8 }).borderRadius(20)
    }.width('100%').padding({ left: 22, right: 22, top: 14, bottom: 13 })
  }
  @Builder
  drillBanner() {
    Row({ space: 7 }) {
      Text('EXERCISE').fontSize(9).fontWeight(FontWeight.Bold).fontColor('#795D2C')
      Text('Hackathon prototype · not an official warning').fontSize(10).fontColor('#795D2C')
    }.width('100%').justifyContent(FlexAlign.Center).padding(8).backgroundColor('#F1EBDD')
  }
  @Builder
  sectionTitle(kicker: string, title: string) {
    Column({ space: 6 }) {
      Text(kicker).fontSize(10).letterSpacing(1.5).fontWeight(FontWeight.Bold).fontColor(MUTED)
      Text(title).fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK).letterSpacing(-0.6)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  primaryButton(label: () => string, id: string, action: () => void) {
    Button(label()).id(id).width('100%').height(48).fontSize(14).fontWeight(FontWeight.Bold)
      .fontColor(LIME).backgroundColor(INK).borderRadius(15).onClick(action)
  }

  @Builder
  homeView() {
    Column({ space: 18 }) {
      Column({ space: 9 }) {
        Text('A LITTLE PREPARATION. A STRONGER COMMUNITY.').fontSize(9).letterSpacing(1).fontColor(MUTED)
        Text('Stay informed.\nStay connected.').fontSize(36).lineHeight(41).fontWeight(FontWeight.Bold)
          .fontColor(INK).letterSpacing(-1.1)
        Text('When the network stops, care keeps moving.').fontSize(13).fontColor(MUTED)
      }.width('100%').alignItems(HorizontalAlign.Start)
      Column({ space: 12 }) {
        Row() {
          Text('YOUR OFFLINE AREA').fontSize(10).fontWeight(FontWeight.Bold).letterSpacing(1).fontColor(INK)
          Blank()
          Text('✓  ON THIS PHONE').fontSize(9).fontWeight(FontWeight.Bold).fontColor(INK)
        }.width('100%')
        Stack({ alignContent: Alignment.BottomStart }) {
          OfflineMap({ vm: this.map, revision: this.mapRevision, compact: true,
            onSelect: (id: string) => { this.selectPoint(id); this.selectTab(1); } })
          Text('Kraków · centrum').fontSize(14).fontWeight(FontWeight.Bold).fontColor(INK)
            .backgroundColor('#F9FCF3').padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(9).margin(12)
        }.height(166).width('100%').borderRadius(16).clip(true)
        Text(this.map.attribution).fontSize(8).fontColor(MUTED).width('100%')
        Row() {
          Column({ space: 3 }) {
            Text(this.map.points.length + ' protective points').fontSize(15).fontWeight(FontWeight.Bold).fontColor(INK)
            Text('PSP data · selected area · stored offline').fontSize(10).fontColor(MUTED)
          }.alignItems(HorizontalAlign.Start)
          Blank()
          Button('Explore ↗').id('exploreMap').fontSize(12).fontColor(INK).fontWeight(FontWeight.Bold)
            .backgroundColor(LIME).height(34).onClick(() => { this.selectTab(1); })
        }.width('100%')
      }.padding(16).width('100%').backgroundColor('#E4ECD9').borderRadius(23)
      Column({ space: 11 }) {
        Row() {
          Text(this.alerts.received ? '✓  SIGNED EXERCISE' : '○  VERIFIED ALERTS').fontSize(10)
            .fontWeight(FontWeight.Bold).fontColor('#896234').letterSpacing(0.8)
          Blank()
          Text('DEMO').fontSize(9).fontWeight(FontWeight.Bold).fontColor('#896234')
        }.width('100%')
        Text(this.alerts.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Text(this.alerts.body).fontSize(12).lineHeight(18).fontColor(MUTED)
        if (this.alerts.received) {
          Text(this.alerts.verification).fontSize(10).fontWeight(FontWeight.Medium).fontColor('#246348')
          Text('Valid until ' + this.alerts.expiry).fontSize(10).fontColor(MUTED)
          Text(this.alerts.persistenceStatus).fontSize(10).fontColor(MUTED)
        }
        this.primaryButton((): string => this.alerts.busy ? 'Verifying…' : this.alerts.received ? 'See how it travels →' : 'Receive a signed drill →',
          'receiveDrill', () => { if (this.alerts.received) { this.selectTab(2); } else { this.loadDrill(); } })
      }.width('100%').alignItems(HorizontalAlign.Start).padding(18).backgroundColor('#F4ECDD').borderRadius(22)
      Row({ space: 12 }) {
        Text('↗').fontSize(29).fontColor(INK).width(38)
        Column({ space: 4 }) {
          Text('One phone can reach the next.').fontSize(14).fontWeight(FontWeight.Bold).fontColor(INK)
          Text('Explore the relay demo — no mobile network needed.').fontSize(11).lineHeight(16).fontColor(MUTED)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ left: 5, right: 5, bottom: 8 }).onClick(() => { this.selectTab(2); })
    }.padding(22).width('100%')
  }

  @Builder
  mapView() {
    Column({ space: 16 }) {
      this.sectionTitle('YOUR AREA, ALWAYS WITH YOU', 'Find a protective point')
      Text('Central Kraków · selected PSP locations').fontSize(12).fontColor(MUTED).width('100%')
      Stack({ alignContent: Alignment.TopEnd }) {
        OfflineMap({ vm: this.map, revision: this.mapRevision,
          onSelect: (id: string) => { this.selectPoint(id); } })
        Column({ space: 7 }) {
          Button('+').id('zoomIn').width(36).height(36).padding(0).fontColor(INK).backgroundColor('#FFFFFF').fontSize(22)
            .onClick(() => { this.map.changeZoom(0.5); this.mapRevision++; })
          Button('−').id('zoomOut').width(36).height(36).padding(0).fontColor(INK).backgroundColor('#FFFFFF').fontSize(22)
            .onClick(() => { this.map.changeZoom(-0.5); this.mapRevision++; })
          Button('◎').id('recenterMap').width(36).height(36).padding(0).fontColor(INK).backgroundColor('#FFFFFF').fontSize(20)
            .onClick(() => { this.map.recenter(); this.mapRevision++; })
        }.margin(12)
      }.height(290).width('100%').borderRadius(22).clip(true)
      Text(this.map.attribution).fontSize(8).fontColor(MUTED).width('100%')
      Text('Blue dot: demo origin at Rynek · tap a map point').fontSize(10).fontColor(MUTED).width('100%')
      Column({ space: 8 }) {
        Row() {
          Text('SELECTED POINT').fontSize(10).fontWeight(FontWeight.Bold).fontColor(MUTED)
          Blank()
          Text(this.map.selected().distanceLabel).fontSize(12).fontWeight(FontWeight.Bold).fontColor(INK)
        }.width('100%')
        Text(this.map.selected().address).fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Text('Miejsce ochronne · ' + this.map.selected().availability).fontSize(12).fontColor(MUTED)
        Text('PSP protective location. Access is not confirmed live. This is not a certified bomb-shelter guarantee.').fontSize(11).lineHeight(16).fontColor(MUTED)
        this.primaryButton((): string => this.map.savedId === this.map.selectedId ? '✓  Saved on this phone' : 'Save this point', 'savePoint', () => { this.savePoint(); })
      }.alignItems(HorizontalAlign.Start).padding(18).width('100%').backgroundColor('#FFFFFF').borderRadius(20)
      Text('NEAR THE DEMO ORIGIN').fontSize(10).letterSpacing(1.3).fontWeight(FontWeight.Bold).fontColor(MUTED).width('100%')
      ForEach(this.map.points.slice(0, 8), (point: SafePointViewModel) => {
        Row({ space: 11 }) {
          Text('+').fontSize(20).fontColor(INK).backgroundColor('#E3EDDA').width(34).height(36)
            .textAlign(TextAlign.Center).borderRadius(10)
          Column({ space: 4 }) {
            Text(point.address).fontSize(13).fontWeight(FontWeight.Bold).fontColor(INK)
            Text(point.availability).fontSize(10).fontColor(MUTED)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text(point.distanceLabel).fontSize(12).fontWeight(FontWeight.Bold).fontColor(INK)
        }.width('100%').padding(12).backgroundColor('#FFFFFF').borderRadius(13)
          .onClick(() => { this.selectPoint(point.id); })
      }, (point: SafePointViewModel) => point.id)
      Text('Distances are straight-line from the demo origin, not walking routes. This is a limited extract, not a complete list.').fontSize(10).lineHeight(15).fontColor(MUTED)
      Text(this.map.attribution + '\nDataset publication: ' + this.map.sourceDate + ' · ' + this.map.packSize + ' bundled').fontSize(9).lineHeight(14).fontColor(MUTED)
    }.padding(22).width('100%')
  }

  @Builder
  nodeBadge(letter: string, label: string, level: number) {
    Column({ space: 7 }) {
      Text(letter).fontSize(23).fontWeight(FontWeight.Bold).fontColor(this.relay.stage >= level ? INK : '#93A394')
        .width(57).height(57).textAlign(TextAlign.Center).borderRadius(29)
        .backgroundColor(this.relay.stage >= level ? LIME : '#EEF2E9')
      Text(label).fontSize(10).fontWeight(FontWeight.Medium).fontColor(INK)
    }
  }
  @Builder
  relayView() {
    Column({ space: 17 }) {
      this.sectionTitle('A MESSAGE WORTH PASSING ON', 'A network of people')
      Text('Keep the signature. Pass the message.').fontSize(13).fontColor(MUTED).width('100%')
      Column({ space: 20 }) {
        Row() {
          Text('3-PHONE SIMULATION').fontSize(10).fontWeight(FontWeight.Bold).fontColor(INK).letterSpacing(1)
          Blank()
          Text('NO RADIO USED').fontSize(9).fontColor(MUTED)
        }.width('100%')
        Row() {
          this.nodeBadge('A', 'First receiver', 1)
          Text('···').fontSize(28).fontColor('#AAC388').layoutWeight(1).textAlign(TextAlign.Center)
          this.nodeBadge('B', 'Relay phone', 2)
          Text('···').fontSize(28).fontColor('#AAC388').layoutWeight(1).textAlign(TextAlign.Center)
          this.nodeBadge('C', 'Next neighbour', 3)
        }.width('100%')
        Text(this.relay.testStatus).fontSize(12).lineHeight(17).fontColor(INK).textAlign(TextAlign.Center)
        this.primaryButton((): string => this.relay.running ? 'Verifying and relaying…' : 'Run the signed relay drill →', 'runRelay', () => { this.relay.simulate(); })
      }.padding(18).backgroundColor('#E4ECD9').borderRadius(22)
      if (this.relay.events.length > 0) {
        ForEach(this.relay.events, (event: RelayEvent) => {
          Row({ space: 10 }) {
            Text(event.good ? '✓' : '!').fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor(event.good ? '#316643' : '#A94A37').width(24)
            Column({ space: 3 }) {
              Text(event.title).fontSize(13).fontWeight(FontWeight.Bold).fontColor(INK)
              Text(event.detail).fontSize(10).lineHeight(15).fontColor(MUTED)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.padding(10).width('100%').backgroundColor('#FFFFFF').borderRadius(12)
        }, (event: RelayEvent) => event.id)
      }
      Column({ space: 11 }) {
        Row() {
          Text('NearLink').fontSize(19).fontWeight(FontWeight.Bold).fontColor(INK)
          Blank()
          Text(this.relay.peerCount + ' connected').fontSize(10).fontColor(MUTED)
        }.width('100%')
        Text(this.relay.hardwareStatus).fontSize(12).lineHeight(18).fontColor(MUTED).id('nearlinkStatus')
        Button('Check hardware').id('checkNearLink').width('100%').height(40).fontSize(12)
          .backgroundColor('#E7EEDD').fontColor(INK).onClick(() => { this.relay.probe(); })
        if (this.relay.hardwareSupported) {
          TextInput({ placeholder: 'Exact name of the nearby phone', text: this.relay.peerName })
            .fontSize(12).onChange((value: string) => { this.relay.peerName = value; })
          this.primaryButton((): string => 'Start relay & discover', 'startHardware', () => { this.relay.startHardware(); })
          ForEach(this.relay.peers, (peer: PeerViewModel) => {
            Button(peer.name + (peer.connected ? ' · connected' : ' · connect')).fontSize(11)
              .onClick(() => { this.relay.connect(peer.address); })
          }, (peer: PeerViewModel) => peer.address)
          Button('Share verified alert').fontSize(12).onClick(() => { this.relay.share(); })
          Button('Stop radio relay').fontSize(12).onClick(() => { this.relay.stop(); })
        }
        Text('The native NearLink adapter is included. Two compatible physical phones are needed to test radio delivery. Keep the app in the foreground.').fontSize(10).lineHeight(15).fontColor(MUTED)
      }.padding(18).width('100%').alignItems(HorizontalAlign.Start).backgroundColor('#FFFFFF').borderRadius(20)
    }.padding(22).width('100%')
  }

  @Builder
  guideItem(number: string, title: string, detail: string) {
    Row({ space: 13 }) {
      Text(number).fontSize(14).fontWeight(FontWeight.Bold).fontColor(INK).width(34).height(34)
        .textAlign(TextAlign.Center).backgroundColor(LIME).borderRadius(11)
      Column({ space: 6 }) {
        Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(INK)
        Text(detail).fontSize(12).lineHeight(18).fontColor(MUTED)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Top).padding(17).backgroundColor('#FFFFFF').borderRadius(18)
  }
  @Builder
  guideView() {
    Column({ space: 17 }) {
      this.sectionTitle('PREPARE BEFORE YOU NEED IT', 'A plan, not a panic')
      Text('A short offline reminder based on Poland’s public safety guide. Follow current instructions from the authorities.').fontSize(13).lineHeight(19).fontColor(MUTED)
      this.guideItem('01', 'Know your nearby options', 'Explore protective points before an emergency. Check the actual entrance and access conditions. A map marker cannot confirm that a place is open or safe to reach.')
      this.guideItem('02', 'Keep essentials ready', 'Prepare your evacuation bag and a household plan in advance. Include what you personally need, and keep your phone and power bank charged.')
      this.guideItem('03', 'Follow verified instructions', 'Read official alerts carefully. If evacuation is ordered, follow the designated directions. Check whether neighbours know about the alert and let loved ones know your plan.')
      this.guideItem('04', 'Help information travel', 'With compatible phones, keep SafeMesh open to relay signed messages. Relaying cannot overcome jamming, a lack of nearby devices, or a compromised signing authority.')
      Column({ space: 9 }) {
        Text('What “verified” means here').fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK)
        Text('This prototype verifies a pinned exercise key using ECDSA P-256. It is not connected to RCB. A real service needs an authorised issuer, secure key custody, rotation and revocation. Forwarders cannot edit signed content without detection.').fontSize(12).lineHeight(19).fontColor(MUTED)
        Text('Expired and repeated packets are suppressed. Hop counts limit honest relays; malicious peers may reset them. Device clock accuracy matters.').fontSize(11).lineHeight(17).fontColor(MUTED)
      }.padding(18).backgroundColor('#E4ECD9').borderRadius(20)
      Text('Sources stored with the project:\ngov.pl/web/poradnikbezpieczenstwa\ngov.pl/web/poradnikbezpieczenstwa/ewakuacja\nPSP “Gdzie się ukryć” · dane.gov.pl\nMap: © OpenStreetMap contributors, ODbL').fontSize(10).lineHeight(17).fontColor(MUTED)
      Column({ space: 12 }) {
        Text('SOURCE & LICENCE LINKS').fontSize(10).fontWeight(FontWeight.Bold).fontColor(MUTED)
        Hyperlink('https://www.openstreetmap.org/copyright', 'OpenStreetMap contributors · ODbL').color(INK)
        Hyperlink('https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce', 'KG PSP · protective-point dataset').color(INK)
        Hyperlink('https://creativecommons.org/licenses/by/4.0/', 'PSP data licence · CC BY 4.0').color(INK)
        Hyperlink('https://www.gov.pl/web/poradnikbezpieczenstwa', 'Poland’s public safety guide').color(INK)
        Text('External links open in your browser and need connectivity. The bundled map and guide remain offline.').fontSize(10).lineHeight(15).fontColor(MUTED)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.padding(22).width('100%')
  }

  @Builder
  navItem(index: number, icon: string, label: string) {
    Column({ space: 4 }) {
      Text(icon).fontSize(21).height(26).fontWeight(FontWeight.Bold).fontColor(this.tab === index ? INK : '#8D9A8F')
      Text(label).fontSize(10).height(14).fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.tab === index ? INK : '#8D9A8F')
    }.layoutWeight(1).height(55).justifyContent(FlexAlign.Center).borderRadius(13)
      .backgroundColor(this.tab === index ? '#E4ECD9' : '#FFFFFF')
      .id('tab' + index).onClick(() => { this.selectTab(index); })
  }
  build() {
    Column() {
      this.header()
      this.drillBanner()
      if (this.notice.length > 0) {
        Text(this.notice).fontSize(11).fontColor(INK).padding(9).backgroundColor(LIME).width('100%')
          .onClick(() => { this.notice = ''; })
      }
      Scroll(this.pageScroll) {
        Column() {
          if (this.tab === 0) { this.homeView() }
          else if (this.tab === 1) { this.mapView() }
          else if (this.tab === 2) { this.relayView() }
          else { this.guideView() }
        }.width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      Row({ space: 5 }) {
        this.navItem(0, '⌂', 'Home')
        this.navItem(1, '⌖', 'Map')
        this.navItem(2, '⋯', 'Relay')
        this.navItem(3, '≡', 'Guide')
      }.width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 }).backgroundColor('#FFFFFF')
    }.width('100%').height('100%').backgroundColor(PAPER)
  }
}
