import SwiftUI

struct AgeGroupPicker: View {
    @Binding var selection: AgeGroup?

    var body: some View {
        Picker("연령대", selection: $selection) {
            Text("선택").tag(nil as AgeGroup?)
            ForEach(AgeGroup.allCases, id: \.self) { group in
                Text(group.rawValue).tag(Optional(group))
            }
        }
    }
}
