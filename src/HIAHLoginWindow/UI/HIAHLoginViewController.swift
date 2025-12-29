import UIKit
import Roxas
import AltSign

// MARK: - Delegate Protocol (for ObjC interop)
@objc protocol HIAHLoginViewControllerDelegate: AnyObject {
    @objc func loginDidSucceed()
}

@objc(HIAHLoginViewController)
@objcMembers
class HIAHLoginViewController: UIViewController {
    
    // Delegate for login success callback
    weak var delegate: HIAHLoginViewControllerDelegate?
    
    // UI Elements
    private let stackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let cancelButton = UIButton(type: .system)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Stack View
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
        
        // Title
        titleLabel.text = "Sign in with Apple ID"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center
        stackView.addArrangedSubview(titleLabel)
        
        // Email
        emailField.placeholder = "Apple ID"
        emailField.borderStyle = .roundedRect
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        stackView.addArrangedSubview(emailField)
        
        // Password
        passwordField.placeholder = "Password"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        stackView.addArrangedSubview(passwordField)
        
        // Login Button
        loginButton.setTitle("Sign In", for: .normal)
        loginButton.backgroundColor = .systemBlue
        loginButton.setTitleColor(.white, for: .normal)
        loginButton.layer.cornerRadius = 8
        loginButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        loginButton.addTarget(self, action: #selector(handleLogin), for: .touchUpInside)
        stackView.addArrangedSubview(loginButton)
        
        // Activity Indicator
        activityIndicator.hidesWhenStopped = true
        stackView.addArrangedSubview(activityIndicator)
        
        // Status Label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        stackView.addArrangedSubview(statusLabel)
        
        // Footer Note
        let noteLabel = UILabel()
        noteLabel.text = "Your credentials are sent directly to Apple. HIAH Desktop uses them to sign apps for your device."
        noteLabel.numberOfLines = 0
        noteLabel.textAlignment = .center
        noteLabel.font = .preferredFont(forTextStyle: .caption2)
        noteLabel.textColor = .tertiaryLabel
        stackView.addArrangedSubview(noteLabel)
    }
    
    @objc private func handleLogin() {
        guard let email = emailField.text, !email.isEmpty,
              let password = passwordField.text, !password.isEmpty else {
            statusLabel.text = "Please enter both email and password."
            return
        }
        
        startLoading()
        
        // Set up 2FA handler before login
        HIAHAccountManager.shared.twoFactorHandler = { [weak self] callback in
            DispatchQueue.main.async {
                self?.show2FAPrompt(callback: callback)
            }
        }
        
        Task {
            do {
                let account = try await HIAHAccountManager.shared.login(appleID: email, password: password)
                await MainActor.run {
                    self.stopLoading()
                    self.statusLabel.text = "✅ Signed in as \(account.name)"
                    self.statusLabel.textColor = .systemGreen
                    
                    // Notify delegate
                    print("[LoginVC] Calling delegate?.loginDidSucceed()")
                    self.delegate?.loginDidSucceed()
                    
                    // Also post notification for observers
                    print("[LoginVC] Posting HIAHLoginSuccess notification")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("HIAHLoginSuccess"),
                        object: nil,
                        userInfo: ["account": account]
                    )
                    print("[LoginVC] Notification posted")
                }
            } catch {
                await MainActor.run {
                    self.stopLoading()
                    self.statusLabel.text = "❌ Error: \(error.localizedDescription)"
                    self.statusLabel.textColor = .systemRed
                }
            }
        }
    }
    
    private func show2FAPrompt(callback: @escaping (String?) -> Void) {
        let alert = UIAlertController(
            title: "Two-Factor Authentication",
            message: "Enter the verification code sent to your trusted devices",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Verification Code"
            textField.keyboardType = .numberPad
            textField.textContentType = .oneTimeCode
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            callback(nil)
        })
        
        alert.addAction(UIAlertAction(title: "Verify", style: .default) { _ in
            let code = alert.textFields?.first?.text
            callback(code)
        })
        
        present(alert, animated: true)
    }
    
    private func startLoading() {
        view.isUserInteractionEnabled = false
        loginButton.isEnabled = false
        loginButton.alpha = 0.5
        activityIndicator.startAnimating()
        statusLabel.text = "Authenticating..."
        statusLabel.textColor = .secondaryLabel
    }
    
    private func stopLoading() {
        view.isUserInteractionEnabled = true
        loginButton.isEnabled = true
        loginButton.alpha = 1.0
        activityIndicator.stopAnimating()
    }
}
