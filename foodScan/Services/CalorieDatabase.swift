//
//  CalorieDatabase.swift
//  foodScan
//
//  "Knowledge base" yang dipakai oleh Calorie Estimation Agent.
//  Memetakan 101 label kelas Food101 -> perkiraan kalori per porsi (kkal).
//  Angka bersifat estimasi rata-rata umum (sumber gabungan database gizi publik)
//  dan ditujukan untuk demo/edukasi, bukan saran medis.
//

import Foundation

/// Sumber data kalori statis. Dibungkus service agar mudah diganti
/// (misalnya nanti diganti panggilan API) tanpa mengubah Agent.
enum CalorieDatabase {

    /// Kalori per porsi (kkal) untuk tiap raw label Food101.
    static let table: [String: Int] = [
        "apple_pie": 296, "baby_back_ribs": 470, "baklava": 334, "beef_carpaccio": 190,
        "beef_tartare": 220, "beet_salad": 160, "beignets": 390, "bibimbap": 490,
        "bread_pudding": 310, "breakfast_burrito": 430, "bruschetta": 200, "caesar_salad": 320,
        "cannoli": 290, "caprese_salad": 250, "carrot_cake": 415, "ceviche": 180,
        "cheesecake": 401, "cheese_plate": 420, "chicken_curry": 380, "chicken_quesadilla": 510,
        "chicken_wings": 430, "chocolate_cake": 371, "chocolate_mousse": 355, "churros": 280,
        "clam_chowder": 200, "club_sandwich": 590, "crab_cakes": 290, "creme_brulee": 340,
        "croque_madame": 500, "cup_cakes": 305, "deviled_eggs": 150, "donuts": 280,
        "dumplings": 280, "edamame": 120, "eggs_benedict": 480, "escargots": 190,
        "falafel": 333, "filet_mignon": 350, "fish_and_chips": 600, "foie_gras": 460,
        "french_fries": 365, "french_onion_soup": 250, "french_toast": 350, "fried_calamari": 300,
        "fried_rice": 333, "frozen_yogurt": 220, "garlic_bread": 330, "gnocchi": 250,
        "greek_salad": 210, "grilled_cheese_sandwich": 400, "grilled_salmon": 367, "guacamole": 230,
        "gyoza": 290, "hamburger": 540, "hot_and_sour_soup": 160, "hot_dog": 290,
        "huevos_rancheros": 390, "hummus": 270, "ice_cream": 270, "lasagna": 400,
        "lobster_bisque": 290, "lobster_roll_sandwich": 440, "macaroni_and_cheese": 380, "macarons": 90,
        "miso_soup": 80, "mussels": 170, "nachos": 560, "omelette": 320,
        "onion_rings": 410, "oysters": 130, "pad_thai": 430, "paella": 420,
        "pancakes": 350, "panna_cotta": 290, "peking_duck": 410, "pho": 350,
        "pizza": 285, "pork_chop": 290, "poutine": 740, "prime_rib": 400,
        "pulled_pork_sandwich": 430, "ramen": 440, "ravioli": 380, "red_velvet_cake": 370,
        "risotto": 350, "samosa": 260, "sashimi": 200, "scallops": 140,
        "seaweed_salad": 100, "shrimp_and_grits": 380, "spaghetti_bolognese": 420, "spaghetti_carbonara": 500,
        "spring_rolls": 250, "steak": 460, "strawberry_shortcake": 350, "sushi": 300,
        "tacos": 320, "takoyaki": 320, "tiramisu": 400, "tuna_tartare": 200,
        "waffles": 410
    ]

    /// Nilai default kalau label tidak dikenal.
    static let defaultCalories = 250

    static func calories(for rawLabel: String) -> Int {
        table[rawLabel] ?? defaultCalories
    }

    /// Daftar semua label yang dikenal (dipakai mock & test).
    static var allLabels: [String] { Array(table.keys) }
}
