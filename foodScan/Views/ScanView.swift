//
//  ScanView.swift
//  foodScan
//
//  Layar scan tema terang: preview kartu putih, tombol merah, hasil pipeline.
//

import SwiftUI

struct ScanView: View {
    @ObservedObject var viewModel: ScanViewModel
    /// Dipanggil setelah scan sukses agar Home/Riwayat ikut refresh.
    var onScanCompleted: () -> Void

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showFoodChat = false
    @State private var showRecipe = false
    @State private var showBarcode = false

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        imagePreview

                        if viewModel.isProcessing {
                            HStack(spacing: 10) {
                                ProgressView().tint(Color.brand)
                                Text(viewModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .cardStyle(cornerRadius: 18)
                        }

                        if let hint = viewModel.portionHint {
                            PortionHintCard(hint: hint)
                        }

                        if let result = viewModel.result {
                            ScanResultView(result: result)

                            if viewModel.isEnriching {
                                HStack(spacing: 8) {
                                    ProgressView().tint(Color.brand)
                                    Text("Analyzing nutrition & alternatives…")
                                        .font(.caption).foregroundStyle(Color.secondaryText)
                                }
                            }
                            if !viewModel.whatIfAlternatives.isEmpty {
                                WhatIfCard(alternatives: viewModel.whatIfAlternatives)
                            }
                            VoiceCorrectionButton { transcript in
                                await viewModel.applyVoiceCorrection(transcript: transcript)
                            }
                        }

                        if let aiError = viewModel.aiError {
                            Label(aiError, systemImage: "wand.and.stars")
                                .font(.caption2)
                                .foregroundStyle(Color.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let error = viewModel.errorMessage {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(Color.brand)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if viewModel.selectedImage != nil {
                                    Button {
                                        Task {
                                            await viewModel.scan()
                                            if viewModel.result != nil { onScanCompleted() }
                                        }
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(GlassButtonStyle())
                                    .disabled(viewModel.isProcessing)
                                }
                            }
                            .cardStyle(cornerRadius: 18)
                        }

                        actionButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                    .appContentWidth()
                }
            }
            .navigationTitle("Scan Food")
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera) { image in
                    viewModel.selectedImage = image
                    viewModel.result = nil
                }
            }
            .sheet(isPresented: $showLibrary) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    viewModel.selectedImage = image
                    viewModel.result = nil
                }
            }
            .sheet(isPresented: $showFoodChat) {
                FoodChatSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showRecipe) {
                RecipeSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showBarcode) {
                BarcodeScannerSheet { code in
                    Task {
                        await viewModel.logBarcode(code)
                        if viewModel.result != nil { onScanCompleted() }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: viewModel.selectedImage) { newImage in
            guard newImage != nil, !viewModel.isProcessing else { return }
            Task {
                await viewModel.scan()
                if viewModel.result != nil { onScanCompleted() }
            }
        }
    }

    private var imagePreview: some View {
        ZStack {
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(ScannerFrame().padding(20))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.brand)
                    Text(viewModel.statusText)
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .cardStyle(cornerRadius: 24, padding: 0)
                .overlay(ScannerFrame().padding(20).opacity(0.4))
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { showCamera = true } label: {
                    Label("Camera", systemImage: "camera")
                }
                .buttonStyle(GlassButtonStyle())

                Button { showLibrary = true } label: {
                    Label("Gallery", systemImage: "photo")
                }
                .buttonStyle(GlassButtonStyle())
            }

            Button { showBarcode = true } label: {
                Label("Scan Barcode", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(viewModel.isProcessing)

            Button {
                Task {
                    await viewModel.scan()
                    if viewModel.result != nil { onScanCompleted() }
                }
            } label: {
                Label("Detect Calories", systemImage: "sparkles")
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            .disabled(viewModel.selectedImage == nil || viewModel.isProcessing)
            .opacity(viewModel.selectedImage == nil || viewModel.isProcessing ? 0.5 : 1)

            if viewModel.result != nil {
                Button {
                    showRecipe = true
                    if viewModel.recipe == nil {
                        Task { await viewModel.generateRecipe() }
                    }
                } label: {
                    Label("Generate Recipe", systemImage: "book.pages")
                }
                .buttonStyle(GlassButtonStyle(prominent: true))

                Button {
                    showFoodChat = true
                } label: {
                    Label("Ask AI", systemImage: "message.fill")
                }
                .buttonStyle(GlassButtonStyle())

                quickChatRow
            }

            if viewModel.selectedImage != nil {
                Button(role: .destructive) {
                    viewModel.reset()
                } label: {
                    Text("Reset")
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
    }

    private var quickChatRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.quickChatSuggestions, id: \.self) { prompt in
                    Button(prompt) {
                        showFoodChat = true
                        Task { await viewModel.askFoodQuestion(prompt) }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
    }
}

/// Bingkai sudut ala viewfinder kamera (mockup Food Scanner).
struct ScannerFrame: View {
    var color: Color = .white
    var lineWidth: CGFloat = 3
    var corner: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: corner)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: corner, y: 0))
                p.move(to: CGPoint(x: w - corner, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: corner))
                p.move(to: CGPoint(x: w, y: h - corner)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - corner, y: h))
                p.move(to: CGPoint(x: corner, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - corner))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.25), radius: 3)
        }
    }
}

private struct FoodChatSheet: View {
    @ObservedObject var viewModel: ScanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(viewModel.chatMessages) { msg in
                            HStack {
                                if msg.role == .assistant {
                                    bubble(msg.text, isUser: false)
                                    Spacer(minLength: 24)
                                } else {
                                    Spacer(minLength: 24)
                                    bubble(msg.text, isUser: true)
                                }
                            }
                        }
                        if viewModel.isAskingAI {
                            HStack(spacing: 8) {
                                ProgressView().tint(Color.brand)
                                Text("AI is typing…")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryText)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                quickPrompts

                HStack(spacing: 8) {
                    TextField("Ask about this food…", text: $input)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let text = input
                        input = ""
                        Task { await viewModel.askFoodQuestion(text) }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAskingAI)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle("Food Chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var quickPrompts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.quickChatSuggestions, id: \.self) { prompt in
                    Button(prompt) {
                        Task { await viewModel.askFoodQuestion(prompt) }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .buttonStyle(GlassButtonStyle())
                    .disabled(viewModel.isAskingAI)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func bubble(_ text: String, isUser: Bool) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isUser ? Color.white : Color.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? Color.brand : Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            )
    }
}

// MARK: - Recipe sheet

private struct RecipeSheet: View {
    @ObservedObject var viewModel: ScanViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                if viewModel.isGeneratingRecipe && viewModel.recipe == nil {
                    VStack(spacing: 12) {
                        ProgressView().tint(Color.brand)
                        Text("Cooking up a recipe…")
                            .font(.subheadline).foregroundStyle(Color.secondaryText)
                    }
                } else if let recipe = viewModel.recipe {
                    ScrollView(showsIndicators: false) {
                        content(recipe)
                            .padding(20)
                            .appContentWidth()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2).foregroundStyle(Color.brand)
                        Text("Couldn't generate a recipe. Please try again.")
                            .font(.subheadline).foregroundStyle(Color.secondaryText)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await viewModel.generateRecipe() }
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Color.brand)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func content(_ recipe: GeneratedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recipe.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.primaryText)

            HStack(spacing: 16) {
                Label("\(recipe.servings) servings", systemImage: "person.2.fill")
                Label("\(recipe.totalTimeMinutes) min", systemImage: "clock.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.brand)

            section("Ingredients", systemImage: "list.bullet") {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color.brand.opacity(0.7)).frame(width: 6, height: 6).padding(.top, 6)
                        Text(item).font(.subheadline).foregroundStyle(Color.primaryText)
                    }
                }
            }

            section("Steps", systemImage: "fork.knife") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.brand, in: Circle())
                        Text(step).font(.subheadline).foregroundStyle(Color.primaryText)
                    }
                }
            }

            if let tips = recipe.tips, !tips.isEmpty {
                section("Tip", systemImage: "lightbulb.fill") {
                    Text(tips).font(.footnote).foregroundStyle(Color.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline).foregroundStyle(Color.primaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
