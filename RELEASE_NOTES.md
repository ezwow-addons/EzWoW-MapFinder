# v2.0.33

### 한국어
- 바다 위에 지역 입구가 표시되던 문제를 고쳤습니다. 헤엄쳐서 넘은 자리는 서로 다른 2명이 기록해야 입구로 표시하고, 유령 상태로 넘은 자리는 기록하지 않습니다.
- EzWoW-Data가 깔려 있으면 예전 데이터가 쓰이던 문제를 고쳤습니다. 애드온에 든 최신 데이터를 먼저 씁니다.
- `/ezshare` 창 "종류별" 탭에서 다른 사용자에게 받아 지금 쓰고 있는 기록 수와 보이는 곳을 볼 수 있습니다.
- 다른 사용자가 알려 준 NPC·몬스터 위치와 채집 위치에 "EzWoW 사용자가 알려 준 위치"·"EzWoW 사용자가 여기서 채집함"을 표시합니다.
- 전투 중이나 던전에서 받은 희귀 몬스터 알림을 버리지 않고, 나온 뒤에 차례로 보여 줍니다.
- 다른 사용자가 본 희귀 몬스터 알림에서 "지도에서 보기"·"대상 지정"을 누르면 모든 출현 지점 대신 그 사용자가 본 자리를 찍습니다.
- 몬스터 위치 보고가 8개 차면 새 보고를 받지 못하던 문제를 고쳤습니다.
- 세계지도 아래 플레이어·마우스 좌표 표시를 끌어서 옮길 수 있습니다(오른쪽 클릭: 처음 위치).
- 지도에 핀이 겹쳐 있을 때 마우스를 올린 핀이 이름표와 함께 맨 위로 올라옵니다.

### English
- Fixed zone exits showing up at sea. A spot crossed swimming now shows only after two players noted it, and crossings as a ghost are no longer noted.
- Fixed older data being used when EzWoW-Data is installed; the addon's own, newer data now comes first.
- The /ezshare "By kind" tab now shows how many records from other players are in use and where they show.
- NPC and monster spots and gathering spots from other EzWoW users are marked as such in their tooltips.
- Rare alerts that arrive in combat or in a dungeon are no longer lost; they show one after another afterwards.
- On a rare another player saw, "Show on map" and "Target" now point at the spot where it was seen instead of every spawn spot.
- Fixed monster spots taking no new reports once 8 were waiting.
- The player and cursor coordinates on the World Map can be dragged to another place (right-click: back to the default place).
- On the map, the hovered pin comes to the front of pins overlapping it, with its label.
