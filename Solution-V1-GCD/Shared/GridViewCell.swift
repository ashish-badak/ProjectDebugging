import UIKit

class GridViewCell: UICollectionViewCell {
    
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var livePhotoBadgeImageView: UIImageView!
    
    var representedAssetIdentifier: String!
    
    var thumbnailImage: UIImage! {
        didSet {
            imageView.image = thumbnailImage
        }
    }
    var livePhotoBadgeImage: UIImage! {
        didSet {
            livePhotoBadgeImageView.image = livePhotoBadgeImage
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        
        
        /// - NOTE: There is no need to redraw shadow in `configure(image:)` call
        ///         It gets redrawn everytime cell configuration is invoked
        ///         So moved it here.
        ///         Also, adjusted some shadow params to drop visually appealing shadow.
        imageView.layer.cornerRadius = 15.0
        imageView.clipsToBounds = true

        contentView.layer.shadowColor = UIColor.gray.cgColor
        contentView.layer.shadowRadius = 2
        contentView.layer.shadowOffset = .zero
        contentView.layer.shadowOpacity = 0.8
        contentView.layer.shouldRasterize = true
        contentView.layer.rasterizationScale = UIScreen.main.scale
    }
    
    func configure(image: UIImage!) {
        imageView.image = image
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        livePhotoBadgeImageView.image = nil
    }
}
