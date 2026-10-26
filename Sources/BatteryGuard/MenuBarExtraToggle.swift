import SwiftUI

/// Schalter für einen Menüleisten-Zusatzwert; hält die gespeicherte Liste und den Schalter synchron.
struct MenuBarExtraToggle: View {
    let item: MenuBarExtraItem
    @AppStorage(MenuBarExtraItem.appStorageKey) private var raw = ""
    @State private var isOn = false

    var body: some View {
        Toggle(item.localizedTitle, isOn: $isOn)
            .onAppear { isOn = MenuBarExtraItem.decode(raw).contains(item) }
            .onChange(of: isOn) { _, enabled in
                if MenuBarExtraItem.decode(raw).contains(item) != enabled { raw = MenuBarExtraItem.toggled(item, in: raw) }
            }
            .onChange(of: raw) { _, value in isOn = MenuBarExtraItem.decode(value).contains(item) }
    }
}
