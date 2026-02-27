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
    var status: HexStatus = .unclaimed
    var isEligible: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .clear
        
        let hostingVC = UIHostingController(
            rootView: HexDetailView(hexID: hexID, status: status, isEligible: isEligible) {
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
        containerView?.bounds ?? .zero
    }
    
    override func presentationTransitionWillBegin() {
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.1)
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
    let status: HexStatus
    let isEligible: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
            VStack{
                VStack {
                    Text(teamTitle(for: status))
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
                        Text("Too far away to claim.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .frame(height: 400)
            .frame(maxWidth: .infinity)
            .glassEffect(in: .rect(cornerRadius: 32))
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
    }
    
    private func teamTitle(for status: HexStatus) -> String {
        switch status {
        case .red: return "Team Red"
        case .orange: return "Team Orange"
        case .yellow: return "Team Yellow"
        case .green: return "Team Green"
        case .blue: return "Team Blue"
        case .indigo: return "Team Indigo"
        case .purple: return "Team Purple"
        case .contested: return "Contested"
        case .unclaimed: return "Unclaimed"
        }
    }
}
