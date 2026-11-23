import Foundation

/// Deterministic educational answers for questions that do not require private
/// measurements. Prevents the offline model from treating missing biometric
/// values as a reason to refuse basic fitness explanations.
enum CoachKnowledge {
    static func answer(_ question: String) -> String? {
        let normalized = question.lowercased()
            .replacingOccurrences(of: "₂", with: "2")
            .filter { !$0.isWhitespace }
        let asksVO2 = normalized.contains("vo2max") || normalized.contains("v02max")
        let asksMeaning = ["kyause", "matlab", "meaning", "explain", "kaam", "purpose", "benefit", "important",
                           "kyahai", "whatisvo2", "whatisv02"].contains { normalized.contains($0) }
        guard asksVO2, asksMeaning else { return nil }
        return """
        VO₂ max batata hai ki intense exercise ke dauran aapki body maximum kitni oxygen use kar sakti hai (mL/kg/min). Running mein ye aerobic fitness aur endurance potential ka useful indicator hai.

        Iska use: training progress track karna, aerobic fitness ka trend dekhna, aur running performance ko context dena. Lekin race timing sirf VO₂ max se decide nahi hoti—running economy, lactate threshold aur training consistency bhi matter karte hain.

        Improve karne ke liye regular easy aerobic runs, controlled tempo sessions aur recovery ke saath occasional intervals helpful hote hain. Aapki personal VO₂ max value mile to main uska trend bhi explain kar sakta hoon.
        """
    }
}
