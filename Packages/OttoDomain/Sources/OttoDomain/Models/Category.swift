/// The fixed category list (spec §5.6).
///
/// Fixed rather than free-form so rollups mean something - free-form categories
/// produce "AI", "ai tools", and "LLM" as three separate lines. `other` plus the
/// subscription's notes field is the escape valve. Raw values are stable strings,
/// never ordinals, so reordering cases can never corrupt stored data.
public enum Category: String, Codable, Hashable, Sendable, CaseIterable {
    case streamingAndVideo = "streaming-and-video"
    case musicAndAudio = "music-and-audio"
    case newsAndReading = "news-and-reading"
    case aiAndSoftwareTools = "ai-and-software-tools"
    case cloudAndStorage = "cloud-and-storage"
    case gaming = "gaming"
    case fitnessAndHealth = "fitness-and-health"
    case foodAndDelivery = "food-and-delivery"
    case shoppingAndMemberships = "shopping-and-memberships"
    case phoneAndInternet = "phone-and-internet"
    case financeAndInsurance = "finance-and-insurance"
    case educationAndCourses = "education-and-courses"
    case other = "other"
}
