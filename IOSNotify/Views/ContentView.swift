import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("iOS Notify")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                bluetoothStatusBadge
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Theme.surface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)

            DeviceListView()
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var bluetoothStatusBadge: some View {
        let bt = BluetoothManager.shared
        let label: String
        let color: Color
        switch bt.bluetoothState {
        case .poweredOn:  label = "BT ON";  color = Theme.accent
        case .poweredOff: label = "BT OFF"; color = .red
        default:          label = "BT …";   color = Theme.dimText
        }
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 1))
    }
}
