//
//  ExampleCheckoutViewController.swift
//  PaymentSheet Example
//
//  Created by Yuki Tokuhiro on 12/4/20.
//  Copyright © 2020 stripe-ios. All rights reserved.
//

import Foundation
@_spi(LinkOnly) import StripePaymentSheet
import UIKit

class ExampleCheckoutViewController: UIViewController {
    @IBOutlet weak var buyButton: UIButton!
    @IBOutlet weak var addBankAccount: UIButton!
    var paymentSheet: PaymentSheet?
    var linkBankPaymentController: LinkPaymentController?

    @IBAction func didTapBankAccount(_ sender: Any) {
        linkBankPaymentController?.present(from: self, completion: { result in
            switch result {

            case .success():
                print("yay")
                DispatchQueue.main.async {
                    self.buyButton.isEnabled = true
                }
            case .failure(let error):
                print("error \(error.localizedDescription)")

            }
        })
    }
    let backendCheckoutUrl = URL(string: "https://abundant-elderly-universe.glitch.me/checkout")!  // An example backend endpoint

    override func viewDidLoad() {
        super.viewDidLoad()

        buyButton.addTarget(self, action: #selector(didTapCheckoutButton), for: .touchUpInside)
        buyButton.isEnabled = false
        addBankAccount.isEnabled = false

        // MARK: Fetch the PaymentIntent and Customer information from the backend
        var request = URLRequest(url: backendCheckoutUrl)
        request.httpMethod = "POST"
        let task = URLSession.shared.dataTask(
            with: request,
            completionHandler: { [weak self] (data, _, _) in
                guard let data = data,
                    let json = try? JSONSerialization.jsonObject(with: data, options: [])
                        as? [String: Any],
                    let customerId = json["customer"] as? String,
                    let customerEphemeralKeySecret = json["ephemeralKey"] as? String,
                    let paymentIntentClientSecret = json["paymentIntent"] as? String,
                    let publishableKey = json["publishableKey"] as? String,
                    let self = self
                else {
                    // Handle error
                    return
                }
                // MARK: Set your Stripe publishable key - this allows the SDK to make requests to Stripe for your account
                STPAPIClient.shared.publishableKey = publishableKey

                // MARK: Create a PaymentSheet instance
                var configuration = PaymentSheet.Configuration()
                configuration.merchantDisplayName = "Example, Inc."
                configuration.customer = .init(
                    id: customerId, ephemeralKeySecret: customerEphemeralKeySecret)
                configuration.returnURL = "payments-example://stripe-redirect"
                // Set allowsDelayedPaymentMethods to true if your business can handle payment methods that complete payment after a delay, like SEPA Debit and Sofort.

                self.linkBankPaymentController = LinkPaymentController(paymentIntentClientSecret: paymentIntentClientSecret, returnURL: configuration.returnURL)

                DispatchQueue.main.async {
                    self.addBankAccount.isEnabled = true
                }
            })
        task.resume()
    }

    @objc
    func didTapCheckoutButton() {
        linkBankPaymentController?.confirm(from: self, completion: { paymentResult in
                        switch paymentResult {
                        case .completed:
                            self.displayAlert("Your order is confirmed!")
                        case .canceled:
                            print("Canceled!")
                        case .failed(let error):
                            print(error)
                            DispatchQueue.main.async {
                                self.displayAlert("Payment failed: \n\(error.localizedDescription)")
                            }
                        }
        })

//        // MARK: Start the checkout process
//        paymentSheet?.present(from: self) { paymentResult in
//            // MARK: Handle the payment result
//            switch paymentResult {
//            case .completed:
//                self.displayAlert("Your order is confirmed!")
//            case .canceled:
//                print("Canceled!")
//            case .failed(let error):
//                print(error)
//                self.displayAlert("Payment failed: \n\(error.localizedDescription)")
//            }
//        }
    }

    func displayAlert(_ message: String) {
        let alertController = UIAlertController(title: "", message: message, preferredStyle: .alert)
        let OKAction = UIAlertAction(title: "OK", style: .default) { (_) in
            alertController.dismiss(animated: true) {
                self.navigationController?.popViewController(animated: true)
            }
        }
        alertController.addAction(OKAction)
        present(alertController, animated: true, completion: nil)
    }
}
