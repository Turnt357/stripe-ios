//
//  UpdateCardViewController.swift
//  StripePaymentSheet
//
//  Created by Nick Porter on 10/27/23.
//
import Foundation
@_spi(STP) import StripeCore
@_spi(STP) import StripePayments
@_spi(STP) import StripePaymentsUI
@_spi(STP) import StripeUICore
import UIKit

protocol UpdateCardViewControllerDelegate: AnyObject {
    func didRemove(paymentOptionCell: SavedPaymentMethodCollectionView.PaymentOptionCell)
    func didUpdate(paymentOptionCell: SavedPaymentMethodCollectionView.PaymentOptionCell,
                   updateParams: STPPaymentMethodUpdateParams) async throws
}

/// For internal SDK use only
@objc(STP_Internal_UpdateCardViewController)
final class UpdateCardViewController: UIViewController {
    private let appearance: PaymentSheet.Appearance
    private let paymentMethod: STPPaymentMethod
    private let paymentOptionCell: SavedPaymentMethodCollectionView.PaymentOptionCell
    private let removeSavedPaymentMethodMessage: String?
    private let isTestMode: Bool
    private let hostedSurface: HostedSurface

    private var latestError: Error? {
        didSet {
            errorLabel.text = latestError?.localizedDescription
            errorLabel.isHidden = latestError == nil
        }
    }

    weak var delegate: UpdateCardViewControllerDelegate?

    // MARK: Navigation bar
    internal lazy var navigationBar: SheetNavigationBar = {
        let navBar = SheetNavigationBar(isTestMode: isTestMode,
                                        appearance: appearance)
        navBar.delegate = self
        navBar.setStyle(.back)
        return navBar
    }()

    // MARK: Views
    lazy var formStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [headerLabel, cardSection.view, updateButton, deleteButton, errorLabel])
        stackView.directionalLayoutMargins = PaymentSheetUI.defaultMargins
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.axis = .vertical
        stackView.spacing = PaymentSheetUI.defaultPadding
        stackView.setCustomSpacing(PaymentSheetUI.defaultPadding - 4, after: headerLabel) // custom spacing from figma
        stackView.setCustomSpacing(32, after: cardSection.view) // custom spacing from figma
        stackView.setCustomSpacing(stackView.spacing / 2, after: updateButton)
        stackView.layoutMargins.bottom = PaymentSheetUI.defaultPadding * 1.1
        return stackView
    }()

    private lazy var headerLabel: UILabel = {
        let label = PaymentSheetUI.makeHeaderLabel(appearance: appearance)
        label.text = .Localized.update_card
        return label
    }()

    private lazy var updateButton: ConfirmButton = {
        return ConfirmButton(state: .disabled, callToAction: .custom(title: .Localized.update_card), appearance: appearance, didTap: {  [weak self] in
            Task {
                await self?.updateCard()
            }
        })
    }()

    private lazy var deleteButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setTitleColor(appearance.colors.danger, for: .normal)
        button.setTitle(.Localized.remove_card, for: .normal)
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.font = appearance.scaledFont(for: appearance.font.base.medium, style: .callout, maximumPointSize: 25)
        button.titleLabel?.adjustsFontForContentSizeCategory = true

        button.addTarget(self, action: #selector(removeCard), for: .touchUpInside)
        return button
    }()

    private lazy var errorLabel: UILabel = {
        let label = ElementsUI.makeErrorLabel(theme: appearance.asElementsTheme)
        label.isHidden = true
        return label
    }()

    // MARK: Elements
    private lazy var panElement: TextFieldElement = {
        return TextFieldElement.LastFourConfiguration(lastFour: paymentMethod.card?.last4 ?? "", cardBrandDropDown: cardBrandDropDown).makeElement(theme: appearance.asElementsTheme)
    }()

    private lazy var cardBrandDropDown: DropdownFieldElement = {
        let cardBrands = paymentMethod.card?.networks?.available.map({ STPCard.brand(from: $0) }) ?? []
        let cardBrandDropDown = DropdownFieldElement.makeCardBrandDropdown(cardBrands: Set<STPCardBrand>(cardBrands),
                                                                           theme: appearance.asElementsTheme,
                                                                           includePlaceholder: false) { [weak self] in
                                                                                guard let self = self else { return }
                                                                                let selectedCardBrand = self.cardBrandDropDown.selectedItem.rawData.toCardBrand ?? .unknown
                                                                                let params = ["selected_card_brand": STPCardBrandUtilities.apiValue(from: selectedCardBrand), "cbc_event_source": "edit"]
                                                                                STPAnalyticsClient.sharedClient.logPaymentSheetEvent(event: self.hostedSurface.analyticEvent(for: .openCardBrandDropdown),
                                                                                                                                                                             params: params)
                                                                            } didTapClose: { [weak self] in
                                                                                guard let self = self else { return }
                                                                                let selectedCardBrand = self.cardBrandDropDown.selectedItem.rawData.toCardBrand ?? .unknown
                                                                                STPAnalyticsClient.sharedClient.logPaymentSheetEvent(event: self.hostedSurface.analyticEvent(for: .closeCardBrandDropDown),
                                                                                                                                     params: ["selected_card_brand": STPCardBrandUtilities.apiValue(from: selectedCardBrand)])
                                                                            }

        // pre-select current card brand
        if let currentCardBrand = paymentMethod.card?.preferredDisplayBrand,
           let indexToSelect = cardBrandDropDown.items.firstIndex(where: { $0.rawData == STPCardBrandUtilities.apiValue(from: currentCardBrand) }) {
            cardBrandDropDown.select(index: indexToSelect, shouldAutoAdvance: false)
        }

        return cardBrandDropDown
    }()

    private lazy var cardSection: SectionElement = {
        let allSubElements: [Element?] = [
            panElement, SectionElement.HiddenElement(cardBrandDropDown),
        ]

        let section = SectionElement(elements: allSubElements.compactMap { $0 }, theme: appearance.asElementsTheme)
        section.delegate = self
        return section
    }()

    // MARK: Overrides
    init(paymentOptionCell: SavedPaymentMethodCollectionView.PaymentOptionCell,
         paymentMethod: STPPaymentMethod,
         removeSavedPaymentMethodMessage: String?,
         appearance: PaymentSheet.Appearance,
         hostedSurface: HostedSurface,
         isTestMode: Bool) {
        self.paymentOptionCell = paymentOptionCell
        self.paymentMethod = paymentMethod
        self.removeSavedPaymentMethodMessage = removeSavedPaymentMethodMessage
        self.appearance = appearance
        self.hostedSurface = hostedSurface
        self.isTestMode = isTestMode

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // disable swipe to dismiss
        isModalInPresentation = true

        let stackView = UIStackView(arrangedSubviews: [formStackView])
        stackView.spacing = PaymentSheetUI.defaultPadding
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.backgroundColor = appearance.colors.background
        view.backgroundColor = appearance.colors.background
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        STPAnalyticsClient.sharedClient.logPaymentSheetEvent(event: hostedSurface.analyticEvent(for: .openCardBrandEditScreen))
    }

    // MARK: Private helpers
    private func dismiss(didUpdate: Bool = false) {
        guard let bottomVc = parent as? BottomSheetViewController else { return }
        if !didUpdate {
            STPAnalyticsClient.sharedClient.logPaymentSheetEvent(event: hostedSurface.analyticEvent(for: .closeEditScreen))
        }
        _ = bottomVc.popContentViewController()
    }

    @objc private func removeCard() {
        let alertController = UIAlertController.makeRemoveAlertController(paymentMethod: paymentMethod,
                                                                          removeSavedPaymentMethodMessage: removeSavedPaymentMethodMessage) { [weak self] in
            guard let self = self else { return }
            self.delegate?.didRemove(paymentOptionCell: self.paymentOptionCell)
            self.dismiss()
        }

        present(alertController, animated: true, completion: nil)
    }

    private func updateCard() async {
        guard let selectedBrand = cardBrandDropDown.selectedItem.rawData.toCardBrand, let delegate = delegate else { return }

        view.isUserInteractionEnabled = false
        updateButton.update(state: .spinnerWithInteractionDisabled)

        // Create the update card params
        let cardParams = STPPaymentMethodCardParams()
        cardParams.networks = .init(preferred: STPCardBrandUtilities.apiValue(from: selectedBrand))
        let updateParams = STPPaymentMethodUpdateParams(card: cardParams, billingDetails: nil)

        // Make the API request to update the payment method
        do {
            try await delegate.didUpdate(paymentOptionCell: paymentOptionCell, updateParams: updateParams)
            dismiss(didUpdate: true)
            STPAnalyticsClient.sharedClient.logPaymentSheetEvent(event: hostedSurface.analyticEvent(for: .updateCardBrand),
                                                                 params: ["selected_card_brand": STPCardBrandUtilities.apiValue(from: selectedBrand)])
        } catch {
            updateButton.update(state: .enabled)
            latestError = error
            STPAnalyticsClient.sharedClient.logPaymentSheetEvent(event: hostedSurface.analyticEvent(for: .updateCardBrandFailed),
                                                                 error: error,
                                                                 params: ["selected_card_brand": STPCardBrandUtilities.apiValue(from: selectedBrand)])
        }

        view.isUserInteractionEnabled = true
    }

}

// MARK: BottomSheetContentViewController
extension UpdateCardViewController: BottomSheetContentViewController {

    var allowsDragToDismiss: Bool {
        return view.isUserInteractionEnabled
    }

    func didTapOrSwipeToDismiss() {
        guard view.isUserInteractionEnabled else {
            return
        }

        dismiss()
    }

    var requiresFullScreen: Bool {
        return false
    }
}

// MARK: SheetNavigationBarDelegate
extension UpdateCardViewController: SheetNavigationBarDelegate {

    func sheetNavigationBarDidClose(_ sheetNavigationBar: SheetNavigationBar) {
        dismiss()
    }

    func sheetNavigationBarDidBack(_ sheetNavigationBar: SheetNavigationBar) {
        dismiss()
    }

}

// MARK: ElementDelegate
extension UpdateCardViewController: ElementDelegate {
    func continueToNextField(element: Element) {
        // no-op
    }

    func didUpdate(element: Element) {
        latestError = nil // clear error on new input
        let selectedBrand = cardBrandDropDown.selectedItem.rawData.toCardBrand
        let currentCardBrand = paymentMethod.card?.preferredDisplayBrand ?? .unknown
        let shouldBeEnabled = selectedBrand != currentCardBrand && selectedBrand != .unknown
        updateButton.update(state: shouldBeEnabled ? .enabled : .disabled)
    }
}
