//
//  CardBrandChoiceAvailability.swift
//  StripePaymentSheet
//
//  Created by Nick Porter on 9/5/23.
//

import Foundation

// TODO(porter) Remove this for card brand choice GA
@_spi(STP) public struct CardBrandChoiceAvailability {
    // Only for development/testing purposes
    @_spi(STP) public static var isCardBrandChoiceAvailable = false
}
