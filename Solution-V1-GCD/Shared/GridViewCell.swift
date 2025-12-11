import UIKit
import PhotosUI

class GridViewCell: UICollectionViewCell {
    static let livePhotoBadge = PHLivePhotoView.livePhotoBadgeImage(options: .overContent)
    private static let cornerRadius: CGFloat = 25

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var livePhotoBadgeImageView: UIImageView!
    
    var representedAssetIdentifier: String?
    var imageRequestID: PHImageRequestID?
    var onCellReuse: ((PHImageRequestID) -> Void)?

    private lazy var shadowLayer: CALayer = {
        let layer = CALayer()
        layer.shadowColor = UIColor.gray.cgColor
        layer.shadowRadius = 4
        layer.shadowOffset = .zero
        layer.shadowOpacity = 0.5
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        setupView()
    }
    
    private func setupView() {
        /// - NOTE: Live badge is a in a way static image so setting it only once
        livePhotoBadgeImageView.image = Self.livePhotoBadge
        livePhotoBadgeImageView.isHidden = true
        
        /// - NOTE: There is no need to redraw shadow in `configure(image:)` call
        ///         It gets redrawn everytime cell configuration is invoked
        ///         So moved it here.
        ///         Also, adjusted some shadow params to drop visually appealing shadow.
        imageView.layer.cornerRadius = Self.cornerRadius
        imageView.clipsToBounds = true
        
        /// - NOTE: Setting it false allows layer's content to be drawn outside of the layer's bounds
        ///         This allows us to have more shadowRadius and better fading effect
        layer.masksToBounds = false
        layer.insertSublayer(shadowLayer, at: 0)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if shadowLayer.frame == bounds { return }
        
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: Self.cornerRadius
        ).cgPath
    }
    
    func configure(image: UIImage?, isLiveImage: Bool) {
        imageView.image = image
        
        /// - NOTE: Live image badge is hidden and shown as needed
        livePhotoBadgeImageView.isHidden = isLiveImage == false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let imageRequestID {
            onCellReuse?(imageRequestID)
            self.imageRequestID = nil
            onCellReuse = nil
        }
        imageView.image = nil
        livePhotoBadgeImageView.isHidden = true
    }
}
