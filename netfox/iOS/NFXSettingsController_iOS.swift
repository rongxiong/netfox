//
//  NFXSettingsController_iOS.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

#if os(iOS)
    
import UIKit
import MessageUI

class NFXSettingsController_iOS: NFXSettingsController, UITableViewDelegate, UITableViewDataSource, MFMailComposeViewControllerDelegate, DataCleaner {
    
    var tableView: UITableView = UITableView(frame: .zero, style: .grouped)
    
    // MARK: View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        nfxURL = "https://github.com/kasketis/netfox"
        
        title = "Settings"
        
        tableData = HTTPModelShortType.allCases
        
        edgesForExtendedLayout = UIRectEdge()
        extendedLayoutIncludesOpaqueBars = false
        automaticallyAdjustsScrollViewInsets = false
        
        navigationItem.rightBarButtonItems = [UIBarButtonItem(image: UIImage.NFXStatistics(), style: .plain, target: self, action: #selector(NFXSettingsController_iOS.statisticsButtonPressed)), UIBarButtonItem(image: UIImage.NFXInfo(), style: .plain, target: self, action: #selector(NFXSettingsController_iOS.infoButtonPressed))]
        
        tableView.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: view.frame.height - 60)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.translatesAutoresizingMaskIntoConstraints = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.alwaysBounceVertical = false
        tableView.backgroundColor = UIColor.clear
        tableView.separatorInset = .zero
        tableView.keyboardDismissMode = .onDrag
        
        tableView.tableFooterView = UIView(frame: CGRect.zero)
        tableView.tableFooterView?.isHidden = true
        view.addSubview(tableView)
        
        var nfxVersionLabel: UILabel
        nfxVersionLabel = UILabel(frame: CGRect(x: 10, y: view.frame.height - 60, width: view.frame.width - 2*10, height: 30))
        nfxVersionLabel.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
        nfxVersionLabel.font = UIFont.NFXFont(size: 14)
        nfxVersionLabel.textColor = UIColor.NFXOrangeColor()
        nfxVersionLabel.textAlignment = .center
        nfxVersionLabel.text = nfxVersionString
        view.addSubview(nfxVersionLabel)
        
        var nfxURLButton: UIButton
        nfxURLButton = UIButton(frame: CGRect(x: 10, y: view.frame.height - 40, width: view.frame.width - 2*10, height: 30))
        nfxURLButton.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
        nfxURLButton.titleLabel?.font = UIFont.NFXFont(size: 12)
        nfxURLButton.setTitleColor(UIColor.NFXGray44Color(), for: .init())
        nfxURLButton.titleLabel?.textAlignment = .center
        nfxURLButton.setTitle(nfxURL, for: .init())
        nfxURLButton.addTarget(self, action: #selector(NFXSettingsController_iOS.nfxURLButtonPressed), for: .touchUpInside)
        view.addSubview(nfxURLButton)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        NFXHTTPModelManager.shared.filters = filters
    }
    
    @objc func nfxURLButtonPressed() {
        UIApplication.shared.openURL(URL(string: nfxURL)!)
    }
    
    @objc func infoButtonPressed() {
        var infoController: NFXInfoController_iOS
        infoController = NFXInfoController_iOS()
        navigationController?.pushViewController(infoController, animated: true)
    }
    
    @objc func statisticsButtonPressed() {
        var statisticsController: NFXStatisticsController_iOS
        statisticsController = NFXStatisticsController_iOS()
        navigationController?.pushViewController(statisticsController, animated: true)
    }
    
    // MARK: UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 2
        case 2: return self.tableData.count
        case 3: return 1
        case 4: return 1
        default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.textLabel?.font = UIFont.NFXFont(size: 14)
        cell.textLabel?.textColor = .black
        cell.tintColor = UIColor.NFXOrangeColor()
        cell.backgroundColor = .white
        
        switch indexPath.section {
        case 0:
            cell.textLabel?.text = "Logging"
            let nfxEnabledSwitch: UISwitch
            nfxEnabledSwitch = UISwitch()
            nfxEnabledSwitch.setOn(NFX.sharedInstance().isEnabled(), animated: false)
            nfxEnabledSwitch.addTarget(self, action: #selector(NFXSettingsController_iOS.nfxEnabledSwitchValueChanged(_:)), for: .valueChanged)
            cell.accessoryView = nfxEnabledSwitch
            return cell
            
        case 1:
            return mockCell(for: indexPath.row, reusing: cell)
            
        case 2:
            let shortType = tableData[indexPath.row]
            cell.textLabel?.text = shortType.rawValue
            configureCell(cell, indexPath: indexPath)
            return cell
            
        case 3:
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.text = "Share Session Logs"
            cell.textLabel?.textColor = UIColor.NFXGreenColor()
            cell.textLabel?.font = UIFont.NFXFont(size: 16)
            return cell
            
        case 4:
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.text = "Clear data"
            cell.textLabel?.textColor = UIColor.NFXRedColor()
            cell.textLabel?.font = UIFont.NFXFont(size: 16)
            
            return cell
            
        default: return UITableViewCell()

        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 5
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView()
        headerView.backgroundColor = UIColor.NFXGray95Color()
        
        switch section {
        case 1:
            
            var mockInfoLabel: UILabel
            mockInfoLabel = UILabel(frame: headerView.bounds)
            mockInfoLabel.backgroundColor = UIColor.clear
            mockInfoLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            mockInfoLabel.font = UIFont.NFXFont(size: 13)
            mockInfoLabel.textColor = UIColor.NFXGray44Color()
            mockInfoLabel.textAlignment = .center
            mockInfoLabel.text = "\nRequests keep their path and query, only the host is replaced"
            mockInfoLabel.numberOfLines = 2
            headerView.addSubview(mockInfoLabel)
            
        case 2:
            
            var filtersInfoLabel: UILabel
            filtersInfoLabel = UILabel(frame: headerView.bounds)
            filtersInfoLabel.backgroundColor = UIColor.clear
            filtersInfoLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            filtersInfoLabel.font = UIFont.NFXFont(size: 13)
            filtersInfoLabel.textColor = UIColor.NFXGray44Color()
            filtersInfoLabel.textAlignment = .center
            filtersInfoLabel.text = "\nSelect the types of responses that you want to see"
            filtersInfoLabel.numberOfLines = 2
            headerView.addSubview(filtersInfoLabel)
            
            
        default: break
        }
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case 1:
            if indexPath.row == 1 {
                (tableView.cellForRow(at: indexPath)?.accessoryView as? UITextField)?.becomeFirstResponder()
            }
        case 2:
            let cell = tableView.cellForRow(at: indexPath)
            self.filters[indexPath.row] = !self.filters[indexPath.row]
            configureCell(cell, indexPath: indexPath)
        case 3:
            shareSessionLogsPressed()
        case 4:
            clearDataButtonPressedOnTableIndex(indexPath)
        default:
            break
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 0: return 44
        case 1: return 44
        case 2: return 33
        case 3,4: return 44
        default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let iPhone4s = (UIScreen.main.bounds.height == 480)
        switch section {
        case 0:
            if iPhone4s {
                return 20
            } else {
                return 40
            }
        case 1:
            if iPhone4s {
                return 40
            } else {
                return 50
            }
        case 2:
            if iPhone4s {
                return 50
            } else {
                return 60
            }
        case 3, 4:
            if iPhone4s {
                return 25
            } else {
                return 50
            }
            
        default: return 0
        }
    }
    
    func configureCell(_ cell: UITableViewCell?, indexPath: IndexPath) {
        cell?.accessoryType = filters[indexPath.row] ? .checkmark : .none
    }
    
    private func mockCell(for row: Int, reusing cell: UITableViewCell) -> UITableViewCell {
        cell.selectionStyle = .none
        
        if row == 0 {
            cell.textLabel?.text = "Mock Server"
            
            let mockServerSwitch: UISwitch
            mockServerSwitch = UISwitch()
            mockServerSwitch.setOn(NFX.sharedInstance().isMockServerEnabled(), animated: false)
            mockServerSwitch.addTarget(self, action: #selector(NFXSettingsController_iOS.mockServerSwitchValueChanged(_:)), for: .valueChanged)
            cell.accessoryView = mockServerSwitch
        } else {
            cell.textLabel?.text = "Server URL"
            
            let textField: UITextField
            textField = UITextField(frame: CGRect(x: 0, y: 0, width: max(120, view.frame.width - 160), height: 30))
            textField.placeholder = "http://localhost:3000"
            textField.text = NFX.sharedInstance().getMockServerURLString()
            textField.font = UIFont.NFXFont(size: 14)
            textField.textColor = UIColor.NFXGray44Color()
            textField.textAlignment = .right
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.keyboardType = .URL
            textField.returnKeyType = .done
            textField.clearButtonMode = .whileEditing
            textField.addTarget(self, action: #selector(NFXSettingsController_iOS.mockURLTextFieldEditingDidEnd(_:)), for: .editingDidEnd)
            textField.addTarget(self, action: #selector(NFXSettingsController_iOS.mockURLTextFieldEditingDidEnd(_:)), for: .editingDidEndOnExit)
            cell.accessoryView = textField
        }
        
        return cell
    }
    
    @objc func nfxEnabledSwitchValueChanged(_ sender: UISwitch) {
        if sender.isOn {
            NFX.sharedInstance().enable()
        } else {
            NFX.sharedInstance().disable()
        }
    }
    
    @objc func mockServerSwitchValueChanged(_ sender: UISwitch) {
        NFX.sharedInstance().setMockServerEnabled(sender.isOn)
    }
    
    @objc func mockURLTextFieldEditingDidEnd(_ sender: UITextField) {
        NFX.sharedInstance().setMockServerURL(sender.text)
    }
    
    func clearDataButtonPressedOnTableIndex(_ index: IndexPath) {
        clearData(sourceView: tableView, originingIn: tableView.rectForRow(at: index)) { }
    }

    func shareSessionLogsPressed() {
        if (MFMailComposeViewController.canSendMail()) {
            let mailComposer = MFMailComposeViewController()
            mailComposer.mailComposeDelegate = self
            
            mailComposer.setSubject("netfox log - Session Log \(NSDate())")
            if let sessionLogData = try? Data(contentsOf: NFXPath.sessionLogURL) {
                mailComposer.addAttachmentData(sessionLogData as Data, mimeType: "text/plain", fileName: NFXPath.sessionLogName)
            }
            
            present(mailComposer, animated: true, completion: nil)
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true, completion: nil)
    }
}

#endif
