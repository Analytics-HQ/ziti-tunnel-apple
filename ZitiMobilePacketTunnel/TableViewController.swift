//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import UIKit
import NetworkExtension
import SafariServices
import MessageUI

class StatusCell: UITableViewCell {
    @IBOutlet weak var connectStatus: UILabel!
    @IBOutlet weak var connectSwitch: UISwitch!
    weak var tvc:TableViewController?
    
    func tunnelStatusDidChange(_ status: NEVPNStatus) {
        switch status {
        case .connecting:
            connectStatus.text = "Connecting..."
            break
        case .connected:
            connectStatus.text = "Connected"
            connectSwitch.isOn = true
            break
        case .disconnecting:
            connectStatus.text = "Disconnecting..."
            break
        case .disconnected:
            connectStatus.text = "Not Connected"
            connectSwitch.isOn = false
            break
        case .invalid:
            connectStatus.text = "Invalid"
            connectSwitch.isOn = false
            break
        case .reasserting:
            connectStatus.text = "Reasserting..."
            break
        @unknown default:
            connectStatus.text = "Unknown"
            connectSwitch.isOn = false
        }
        tvc?.tableView.reloadData()
    }
    
    @IBAction func connectSwitchChanged(_ sender: Any) {
        if connectSwitch.isOn {
            do {
                try tvc?.tunnelMgr.startTunnel()
            } catch {
                let alert = UIAlertController(
                    title:"Ziti Connect Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                tvc?.present(alert, animated: true, completion: nil)
                connectSwitch.isOn = false
            }
        } else {
            tvc?.tunnelMgr.stopTunnel()
        }
    }
}

class TableViewController: UITableViewController, UIDocumentPickerDelegate, MFMailComposeViewControllerDelegate, ZitiIdentityStoreDelegate {
    
    static let providerBundleIdentifier = "io.netfoundry.ZitiMobilePacketTunnel.MobilePacketTunnelProvider"
    var tunnelMgr = TunnelMgr.shared
    var zidMgr = ZidMgr()
    var servicePoller = ServicePoller()
    weak var ivc:IdentityViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        
        Logger.initShared(Logger.APP_TAG)
        NSLog(Version.verboseStr)
        
        // watch for changes to the zids
        zidMgr.zidStore.delegate = self

        // init the manager
        tunnelMgr.loadFromPreferences(TableViewController.providerBundleIdentifier) { tpm, error in
            DispatchQueue.main.async {
                print("done loading from prefs, error=\(error?.localizedDescription ?? "nil")")
                self.tableView.reloadData()
            }
        }
        
        // Load previous identities
        if let err = zidMgr.loadZids() {
            NSLog(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        tableView.reloadData()
        
        servicePoller.zidMgr = zidMgr
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.servicePoller.startPolling { didChange, zid in
                DispatchQueue.main.async {
                    self.ivc?.tableView.reloadData()
                    if didChange {
                        _ = self.zidMgr.zidStore.store(zid)
                        if zid.isEnabled {
                            self.tunnelMgr.restartTunnel()
                        }
                    }
                }
            }
        }
    }
    
    func onNewOrChangedId(_ zid: ZitiIdentity) {
        if let match = zidMgr.zids.first(where: { $0.id == zid.id }) {
            print("\(zid.name):\(zid.id) changed")
            
            // TUN will disable if unable to start for zid
            match.edgeStatus = zid.edgeStatus
            match.enabled = zid.enabled
            
            // always take new service from tunneler...
            match.services = zid.services
            tableView.reloadData()
            ivc?.tableView.reloadData()
        } else {
            print("\(zid.name):\(zid.id) new")
        }
    }
    
    func onRemovedId(_ idString: String) {
    }
    
    // MARK: - Table view data source
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == 1 && indexPath.row == zidMgr.zids.count {
            return true
        }
        return false
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == 1 && indexPath.row == zidMgr.zids.count {
            return .insert
        }
        return .none
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var nRows = 1
        if section == 1 {
            nRows = zidMgr.zids.count + 1
        } else if section == 2 {
            nRows = 4
        }
        return nRows
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell:UITableViewCell?

        // Configure the cell...
        if indexPath.section == 0 {
            cell = tableView.dequeueReusableCell(withIdentifier: "STATUS_CELL", for: indexPath)
            if let statusCell = cell as? StatusCell {
                statusCell.tvc = self
                tunnelMgr.tsChangedCallbacks.append(statusCell.tunnelStatusDidChange)
            }
        } else if indexPath.section == 1 {
            if indexPath.row == zidMgr.zids.count {
                cell = tableView.dequeueReusableCell(withIdentifier: "ADD_IDENTITY_CELL", for: indexPath)
                //let btn = UIButton(type: .contactAdd)
                //btn.isUserInteractionEnabled = false
                //cell?.accessoryView = btn // Lookes better with green insert button...
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_CELL", for: indexPath)
                let zid = zidMgr.zids[indexPath.row]
                cell?.tag = indexPath.row
                cell?.textLabel?.text = zid.name
                cell?.detailTextLabel?.text = zid.id
                
                let tunnelStatus = tunnelMgr.status
                var imageName:String = "StatusNone"
                
                if zid.isEnrolled == true, zid.isEnabled == true, let edgeStatus = zid.edgeStatus {
                    switch edgeStatus.status {
                    case .Available: imageName = (tunnelStatus == .connected) ?
                        "StatusAvailable" : "StatusPartiallyAvailable"
                    case .PartiallyAvailable: imageName = "StatusPartiallyAvailable"
                    case .Unavailable: imageName = "StatusUnavailable"
                    default: imageName = "StatusNone"
                    }
                }
                cell?.imageView?.image = UIImage(named: imageName)
            }
        } else {
            // feedback, help, advanced, about
            if indexPath.row == 0 {
                cell = tableView.dequeueReusableCell(withIdentifier: "FEEDBACK_CELL", for: indexPath)
            } else if indexPath.row == 1 {
                cell = tableView.dequeueReusableCell(withIdentifier: "HELP_CELL", for: indexPath)
            } else if indexPath.row == 2 {
                cell = tableView.dequeueReusableCell(withIdentifier: "ADVANCED_CELL", for: indexPath)
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: "ABOUT_CELL", for: indexPath)
            }
        }
        return cell! // Don't let this happen!
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "" // Ziti Connections"
        } else if section == 1 {
            return "Identities"
        }
        return nil
    }
    
    func deviceName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
                
            }
        }
        if modelCode != nil {
            return String(cString: modelCode!, encoding: .utf8) ?? ""
        } else {
            return ""
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 1 && indexPath.row == zidMgr.zids.count {
            let dp = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
            dp.modalPresentationStyle = .formSheet
            dp.allowsMultipleSelection = false
            dp.delegate = self
            self.present(dp, animated: true, completion: nil)
        } else if indexPath.section == 2 && indexPath.row == 0 {
            // quick 'n dirty support email composer.  TODO: Look into Instabug
            if MFMailComposeViewController.canSendMail() {
                let mail = MFMailComposeViewController()
                mail.mailComposeDelegate = self
                mail.setSubject("Ziti Support (iOS)")
                mail.setToRecipients(["support@netfoundry.io"])
                mail.setMessageBody("\n\n\nVersion: \(Version.str)\nOS \(Version.osVersion)\nDevice: \(deviceName())", isHTML: false)
                if let logger = Logger.shared {
                    if let url = logger.currLog(forTag: Logger.TUN_TAG), let data = try? Data(contentsOf: url) {
                        mail.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
                    }
                    if let url = logger.currLog(forTag: Logger.APP_TAG), let data = try? Data(contentsOf: url) {
                        mail.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
                    }
                }
                self.present(mail, animated: true)
            } else {
                print("Mail view controller not available")
                let alert = UIAlertController(
                    title:"Mail view not available",
                    message: "Please email support@netfoundry.io for assistance",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                self.present(alert, animated: true, completion: nil)
            }
        } else if indexPath.section == 2 && indexPath.row == 1 {
            if let url = URL(string: "https://netfoundry.zendesk.com/hc/en-us/categories/360000991011-Docs-Guides") {
                let vc = SFSafariViewController(url: url)
                present(vc, animated: true)
            }
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        NSLog("picker cancelled")
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        do {
            let url = urls[0]
            try zidMgr.insertFromJWT(url, at: 0)
            tableView.reloadData()
            tableView.selectRow(at: IndexPath(row: 0, section: 1), animated: false, scrollPosition: .none)
            performSegue(withIdentifier: "IDENTITY_SEGUE", sender: self)
        } catch let error as ZitiError {
            let alert = UIAlertController(
                title:"Unable to add identity",
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            present(alert, animated: true, completion: nil)
            NSLog("Unable to add identity: \(error.localizedDescription)")
        } catch {
            let alert = UIAlertController(
                title:"JWT Error",
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            present(alert, animated: true, completion: nil)
            NSLog("JWT Error: \(error.localizedDescription)")
            return
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let avc = segue.destination as? AdvancedViewController {
            avc.tvc = self
        } else if let ivc = segue.destination as? IdentityViewController {
            self.ivc = ivc
            ivc.tvc = self
            if let ip = tableView.indexPathForSelectedRow {
                let cell = tableView.cellForRow(at: ip)
                ivc.zid = zidMgr.zids[cell?.tag ?? 0]
            }
        }
    }
    
    @IBAction func unwindFromIdentity(_ sender:UIStoryboardSegue) {
        ivc = nil
    }
}
