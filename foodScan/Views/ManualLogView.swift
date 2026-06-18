//
//  ManualLogView.swift
//  foodScan
//
//  Log makanan manual via teks (tanpa foto). Pengguna mengetik deskripsi,
//  Groq mengestimasi gizinya (lewat `HistoryViewModel.logManualFood`), lalu
//  entri baru disimpan dan layar ditutup.
//

import SwiftUI

struct ManualLogView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var isSubmitting = false
    @State private var showError = false
    @FocusState private var fieldFocused: Bool

    private var canSubmit: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        intro
                        inputCard
                        submitButton
                    }
                    .padding(20)
                    .appContentWidth()
                }
            }
            .navigationTitle("Manual Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Color.brand)
                }
            }
            .alert("Couldn't save", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't estimate nutrition for this food. Check your connection or try a different description.")
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { fieldFocused = true }
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Describe your food")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primaryText)
            Text("Example: \"a bowl of fried rice with egg\". The AI will estimate its calories & nutrition.")
                .font(.footnote)
                .foregroundStyle(Color.secondaryText)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.subheadline)
                .foregroundStyle(Color.brand)
            TextField("Food description", text: $description, axis: .vertical)
                .lineLimit(3...6)
                .focused($fieldFocused)
                .foregroundStyle(Color.primaryText)
                .submitLabel(.done)
        }
        .cardStyle()
    }

    private var submitButton: some View {
        Button(action: submit) {
            if isSubmitting {
                ProgressView().tint(.white)
            } else {
                Text("Save Entry")
            }
        }
        .buttonStyle(GlassButtonStyle(prominent: true))
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.6)
    }

    private func submit() {
        let text = description
        isSubmitting = true
        Task {
            let success = await viewModel.logManualFood(description: text)
            isSubmitting = false
            if success {
                dismiss()
            } else {
                showError = true
            }
        }
    }
}
