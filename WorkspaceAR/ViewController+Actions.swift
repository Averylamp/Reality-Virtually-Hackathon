/*
See LICENSE folder for this sample’s licensing information.

Abstract:
UI Actions for the main view controller.
*/

import UIKit
import SceneKit

extension ViewController: UIGestureRecognizerDelegate {
    
    enum SegueIdentifier: String {
        case showObjects
    }
    
    // MARK: - Interface Actions
    
    /// Displays the `VirtualObjectSelectionViewController` from the `addObjectButton` or in response to a tap gesture in the `sceneView`.
    @IBAction func showVirtualObjectSelectionViewController() {
        // Ensure adding objects is an available action and we are not loading another object (to avoid concurrent modifications of the scene).
//        print("Screen Tapped")
        guard !addObjectButton.isHidden && !virtualObjectLoader.isLoading else { return }
//        print("Tap valid")
        statusViewController.cancelScheduledMessage(for: .contentPlacement)
        
        if addObjectButton.tag != 100{
            performSegue(withIdentifier: SegueIdentifier.showObjects.rawValue, sender: addObjectButton)
        }else{
            addObjectButton.tag = 0
            DataManager.shared().lockNewNode()
            addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
        }
    }
    
    /// Determines if the tap gesture for presenting the `VirtualObjectSelectionViewController` should be used.
    func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        return virtualObjectLoader.loadedObjects.isEmpty
    }
    
    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        return true
    }
    
    /// - Tag: restartExperience
    func restartExperience() {
        guard isRestartAvailable, !virtualObjectLoader.isLoading else { return }
        isRestartAvailable = false

        statusViewController.cancelAllScheduledMessages()

        virtualObjectLoader.removeAllVirtualObjects()
        addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
        addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])

        resetTracking()
        
        DataManager.shared().fullReset()
        self.checkPrompts()
        self.hideContinueButton()
        self.alignmentPointInstructionsShown = false
        // Disable restart for a while in order to give the session time to restart.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.isRestartAvailable = true
        }
    }
}

extension ViewController: UIPopoverPresentationControllerDelegate {
    
    // MARK: - UIPopoverPresentationControllerDelegate

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // All menus should be popovers (even on iPhone).
        if let popoverController = segue.destination.popoverPresentationController, let button = sender as? UIButton {
            popoverController.delegate = self
            popoverController.sourceView = button
            popoverController.sourceRect = button.bounds
        }
        
        guard let identifier = segue.identifier,
              let segueIdentifer = SegueIdentifier(rawValue: identifier),
              segueIdentifer == .showObjects else { return }
        
        let objectsViewController = segue.destination as! VirtualObjectSelectionViewController
        objectsViewController.view.layoutIfNeeded()
        switch DataManager.shared().lastSelectedObjectSet {
        case 0:
            objectsViewController.sharedObjectDescriptors = DataManager.shared().solarSystemObjects
        case 1:
            objectsViewController.sharedObjectDescriptors = DataManager.shared().chessObjects
        case 2:
            objectsViewController.sharedObjectDescriptors = DataManager.shared().constructionObjects
        default:
            objectsViewController.sharedObjectDescriptors = DataManager.shared().solarSystemObjects
        }
        
        objectsViewController.delegate = self
        
        // Set all rows of currently placed objects to selected.
        for object in virtualObjectLoader.loadedObjects {
            guard let index = VirtualObject.availableObjects.index(of: object) else { continue }
            objectsViewController.selectedVirtualObjectRows.insert(index)
        }
    }
    
}
