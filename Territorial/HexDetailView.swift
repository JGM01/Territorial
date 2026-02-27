//
//  HexDetailView.swift
//  Territorial
//
//  Created by Jacob Germana-McCray on 2/26/26.
//

import UIKit
import SwiftUI

// HexDetailViewController — stays thin, just lifecycle
class HexDetailViewController: UIViewController {
    var hexID: UInt64 = 0
    var isEligible: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .clear
        
        let hostingVC = UIHostingController(
            rootView: HexDetailView(hexID: hexID, isEligible: isEligible) {
                self.dismiss(animated: true) // dismiss callback
            }
        )
        
        hostingVC.view.backgroundColor = .clear
        
        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        hostingVC.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}

// Your custom presentation controller
class HexPopoverPresentationController: UIPresentationController {
    
    private let backdropView = UIView()
    
    override var frameOfPresentedViewInContainerView: CGRect {
        // total control — anchor near tap, center screen, whatever
        guard let container = containerView else { return .zero }
        return CGRect(x: 20, y: container.bounds.midY - 200,
                      width: container.bounds.width - 40, height: 400)
    }
    
    override func presentationTransitionWillBegin() {
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        backdropView.alpha = 0
        containerView?.insertSubview(backdropView, at: 0)
        backdropView.frame = containerView?.bounds ?? .zero
        
        presentedViewController.transitionCoordinator?.animate { _ in
            self.backdropView.alpha = 1
        }
    }
    
    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate { _ in
            self.backdropView.alpha = 0
        }
    }
}

// HexDetailView — all your actual UI
struct HexDetailView: View {
    let hexID: UInt64
    let isEligible: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack{
                Text("Team Red")
                    .font(.title.bold())
                
                Text(String(hexID, radix: 16, uppercase: true))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if isEligible {
                    Button("Claim!") { }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Too far away to vote")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(in: .rect(cornerRadius: 32))
        
    }
}
