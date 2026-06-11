//
//  DetailRowView.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import SwiftUI

struct DetailRowView: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 24)

            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
