//
//  CodeScannerView.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import SwiftUI
import AVFoundation

struct CodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        ScannerViewController(onCode: onCode)
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onCode: (String) -> Void
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "de.datlaeuft.scanner.session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var hasScanned = false
    private var messageLabel: UILabel?

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) wurde nicht implementiert")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestPermissionAndConfigure()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.captureSession.isRunning else {
                return
            }

            self.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else {
                return
            }

            self.captureSession.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        messageLabel?.frame = CGRect(x: 24, y: view.safeAreaInsets.top + 24, width: view.bounds.width - 48, height: 80)
    }

    private func requestPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureSession()
                } else {
                    DispatchQueue.main.async {
                        self?.showMessage("Kamerazugriff wurde nicht erlaubt.")
                    }
                }
            }
        default:
            showMessage("Bitte Kamerazugriff in den iOS-Einstellungen erlauben.")
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else {
                return
            }

            guard let device = AVCaptureDevice.default(for: .video) else {
                DispatchQueue.main.async {
                    self.showMessage("Keine Kamera gefunden.")
                }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureMetadataOutput()

                self.captureSession.beginConfiguration()

                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                }

                if self.captureSession.canAddOutput(output) {
                    self.captureSession.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)

                    let requestedTypes: [AVMetadataObject.ObjectType] = [
                        .qr,
                        .ean8,
                        .ean13,
                        .code128,
                        .code39,
                        .code93,
                        .upce,
                        .pdf417,
                        .dataMatrix
                    ]

                    output.metadataObjectTypes = requestedTypes.filter {
                        output.availableMetadataObjectTypes.contains($0)
                    }
                }

                self.captureSession.commitConfiguration()
                self.isConfigured = true

                DispatchQueue.main.async {
                    let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                    layer.videoGravity = .resizeAspectFill
                    layer.frame = self.view.bounds
                    self.view.layer.insertSublayer(layer, at: 0)
                    self.previewLayer = layer
                    self.showMessage("Code in den Rahmen halten")
                }

                self.captureSession.startRunning()
            } catch {
                DispatchQueue.main.async {
                    self.showMessage("Scanner konnte nicht gestartet werden.")
                }
            }
        }
    }

    private func showMessage(_ text: String) {
        if messageLabel == nil {
            let label = UILabel()
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            label.textAlignment = .center
            label.numberOfLines = 2
            label.layer.cornerRadius = 14
            label.layer.masksToBounds = true
            view.addSubview(label)
            messageLabel = label
        }

        messageLabel?.text = text
        view.setNeedsLayout()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = metadataObject.stringValue else {
            return
        }

        hasScanned = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCode(value)
    }
}
