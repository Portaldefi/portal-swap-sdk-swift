import Foundation

struct GasEstimateResponse: Codable {
    let low: FeeEstimate
    let medium: FeeEstimate
    let high: FeeEstimate
    let estimatedBaseFee: Double
    let networkCongestion: Double
    let latestPriorityFeeRange: [Double]
    let historicalPriorityFeeRange: [Double]
    let historicalBaseFeeRange: [Double]
    let priorityFeeTrend: String
    let baseFeeTrend: String
    let version: String

    enum CodingKeys: String, CodingKey {
        case low
        case medium
        case high
        case estimatedBaseFee
        case networkCongestion
        case latestPriorityFeeRange
        case historicalPriorityFeeRange
        case historicalBaseFeeRange
        case priorityFeeTrend
        case baseFeeTrend
        case version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        low = try container.decode(FeeEstimate.self, forKey: .low)
        medium = try container.decode(FeeEstimate.self, forKey: .medium)
        high = try container.decode(FeeEstimate.self, forKey: .high)
        
        // Convert estimatedBaseFee from String to Double
        let estimatedBaseFeeString = try container.decode(String.self, forKey: .estimatedBaseFee)
        guard let estimatedBaseFeeDouble = Double(estimatedBaseFeeString) else {
            throw DecodingError.dataCorruptedError(forKey: .estimatedBaseFee, in: container, debugDescription: "estimatedBaseFee is not a valid Double")
        }
        estimatedBaseFee = estimatedBaseFeeDouble
        
        networkCongestion = try container.decode(Double.self, forKey: .networkCongestion)
        
        // Convert arrays of String to arrays of Double
        let latestPriorityFeeRangeStrings = try container.decode([String].self, forKey: .latestPriorityFeeRange)
        latestPriorityFeeRange = latestPriorityFeeRangeStrings.compactMap(Double.init)
        
        let historicalPriorityFeeRangeStrings = try container.decode([String].self, forKey: .historicalPriorityFeeRange)
        historicalPriorityFeeRange = historicalPriorityFeeRangeStrings.compactMap(Double.init)
        
        let historicalBaseFeeRangeStrings = try container.decode([String].self, forKey: .historicalBaseFeeRange)
        historicalBaseFeeRange = historicalBaseFeeRangeStrings.compactMap(Double.init)
        
        priorityFeeTrend = try container.decode(String.self, forKey: .priorityFeeTrend)
        baseFeeTrend = try container.decode(String.self, forKey: .baseFeeTrend)
        version = try container.decode(String.self, forKey: .version)
    }
}

// MARK: - FeeEstimate

struct FeeEstimate: Codable {
    let suggestedMaxPriorityFeePerGas: Double
    let suggestedMaxFeePerGas: Double
    let minWaitTimeEstimate: Int
    let maxWaitTimeEstimate: Int

    enum CodingKeys: String, CodingKey {
        case suggestedMaxPriorityFeePerGas
        case suggestedMaxFeePerGas
        case minWaitTimeEstimate
        case maxWaitTimeEstimate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Convert suggestedMaxPriorityFeePerGas from String to Double
        let maxPriorityFeeString = try container.decode(String.self, forKey: .suggestedMaxPriorityFeePerGas)
        guard let maxPriorityFeeDouble = Double(maxPriorityFeeString) else {
            throw DecodingError.dataCorruptedError(forKey: .suggestedMaxPriorityFeePerGas, in: container, debugDescription: "suggestedMaxPriorityFeePerGas is not a valid Double")
        }
        suggestedMaxPriorityFeePerGas = maxPriorityFeeDouble
        
        // Convert suggestedMaxFeePerGas from String to Double
        let maxFeeString = try container.decode(String.self, forKey: .suggestedMaxFeePerGas)
        guard let maxFeeDouble = Double(maxFeeString) else {
            throw DecodingError.dataCorruptedError(forKey: .suggestedMaxFeePerGas, in: container, debugDescription: "suggestedMaxFeePerGas is not a valid Double")
        }
        suggestedMaxFeePerGas = maxFeeDouble
        
        minWaitTimeEstimate = try container.decode(Int.self, forKey: .minWaitTimeEstimate)
        maxWaitTimeEstimate = try container.decode(Int.self, forKey: .maxWaitTimeEstimate)
    }
}
