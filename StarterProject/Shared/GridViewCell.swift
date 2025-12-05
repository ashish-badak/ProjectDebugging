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

    func configure(image: UIImage!) {
        imageView.image = image
        imageView.layer.cornerRadius = 25.0
        imageView.clipsToBounds = true

        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowRadius = 5.0
        contentView.layer.shadowOffset = .init(width: 0.0, height: 0.0)
        contentView.layer.shadowOpacity = 0.5
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        livePhotoBadgeImageView.image = nil
    }
}
