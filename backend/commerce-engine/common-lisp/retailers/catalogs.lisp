;;; catalogs.lisp

#|
Home for every retailer whose Impact-format catalog needs NO
retailer-specific parsing.

To add a retailer: add one (defparameter *...-catalog*) for
its file path, and one (defun load-...), following the existing
patern.
|#

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *catalogs-dir*
    (make-pathname :directory (pathname-directory
				(or *compile-file-truename* *load-truename*))))
  (defparameter *common-lisp-dir*
    (merge-pathnames "../" *catalogs-dir*))
  (load (merge-pathnames "throughput/impact-parser.lisp" *common-lisp-dir*)))


;;; Shared database -- the (retailer, sku) uniqueness constraint on products
;;; suppotrs multiple retailers writing into one database without colliding,
;;; even if two retailers happen to reuse the same sku string.

(defparameter *catalogs-db-path*
  (merge-pathnames "../../database/impact.db" *catalogs-dir*))


;;; load-catalog : retailer catalog-path &optional db-path -> list-of failures
;;; Reads an Impact-format catalog file (tab-delimited, matching the raw feed,
;;; parses it into products with no retailer-specific raw-quantity extraction,
;;; and loads the result into the shared database.

(defun load-catalog (retailer catalog-path &optional (db-path *catalogs-db-path*))
  (let* ((rows (load-delimited catalog-path #\Tab))
	 (products (rows->products (cdr rows) :retailer retailer)))
    (load-products-to-db products db-path)))


;;; ---------------------------------------------------------------
;;; Retailers -- add new ones below, following this pattern.
;;; ---------------------------------------------------------------

;;; SinoCrafted
 
(defparameter *sinocrafted-catalog*
  (merge-pathnames "../../data/sinocrafted/impact-format/Updated-sinocrafted_IR.txt"
		    *catalogs-dir*))
 
(defun load-sinocrafted ()
  (load-catalog "SinoCrafted" *sinocrafted-catalog*))
 
 
;;; Terra
 
(defparameter *terra-catalog*
  (merge-pathnames "../../data/terra/impact-format/Updated-terra_IR.txt"
		    *catalogs-dir*))
 
(defun load-terra ()
  (load-catalog "Terra" *terra-catalog*))


;;; ARCN Home

(defparameter *arcn-home-catalog*
  (merge-pathnames "../../data/arcn-home/impact-format/Updated-arcn-home_IR.txt"
		    *catalogs-dir*))

(defun load-arcn-home ()
  (load-catalog "ARCN Home" *arcn-home-catalog*))


;;; ANRAN

(defparameter *anran-catalog*
  (merge-pathnames "../../data/anran/impact-format/Updated-anran_IR.txt"
		    *catalogs-dir*))

(defun load-anran ()
  (load-catalog "ANRAN" *anran-catalog*))


;;; Dr. Jojo Vitamins

(defparameter *dr-jojo-vitamins-catalog*
  (merge-pathnames "../../data/dr-jojo-vitamins/impact-format/Updated-dr-jojo-vitamins_IR.txt"
		    *catalogs-dir*))

(defun load-dr-jojo-vitamins ()
  (load-catalog "Dr. Jojo Vitamins" *dr-jojo-vitamins-catalog*))


;;; Varla -- Impact directory is "Varla-Amazon" (Amazon-sourced
;;; catalog, unlike the Shopify-sourced ones above/below), but the
;;; retailer itself is just Varla -- dir-name kept as varla-amazon
;;; to match the shell script's GENERIC_RETAILERS entry exactly.

(defparameter *varla-amazon-catalog*
  (merge-pathnames "../../data/varla-amazon/impact-format/Updated-varla-amazon_IR.txt"
		    *catalogs-dir*))

(defun load-varla-amazon ()
  (load-catalog "Varla" *varla-amazon-catalog*))


;;; DOWAN -- Impact's own directory name includes Chinese characters
;;; (DOWAN-LLC-内容产出者); dir-name here is plain ASCII ("dowan") by
;;; deliberate choice, since this is OUR OWN local storage naming,
;;; not something that needs to match Impact's remote directory
;;; structure.

(defparameter *dowan-catalog*
  (merge-pathnames "../../data/dowan/impact-format/Updated-dowan_IR.txt"
		    *catalogs-dir*))

(defun load-dowan ()
  (load-catalog "DOWAN" *dowan-catalog*))


;;; DNT Optics

(defparameter *dnt-optics-catalog*
  (merge-pathnames "../../data/dnt-optics/impact-format/Updated-dnt-optics_IR.txt"
		    *catalogs-dir*))

(defun load-dnt-optics ()
  (load-catalog "DNT Optics" *dnt-optics-catalog*))

;;; --- batch added 2026-08-28 -- 44 retailers below, matching the
;;; same GENERIC_RETAILERS additions in shell/update-onp.sh. See
;;; that file's own note on the 11 of these with more than one
;;; catalog entry under their advertiserId (partial coverage, not a
;;; crash) -- same caveat applies here since these load-fns are what
;;; that script actually calls.

;;; Margovil

(defparameter *margovil-catalog*
  (merge-pathnames "../../data/margovil/impact-format/Updated-margovil_IR.txt"
		    *catalogs-dir*))

(defun load-margovil ()
  (load-catalog "Margovil" *margovil-catalog*))

;;; Venus Swim

(defparameter *venus-swim-catalog*
  (merge-pathnames "../../data/venus-swim/impact-format/Updated-venus-swim_IR.txt"
		    *catalogs-dir*))

(defun load-venus-swim ()
  (load-catalog "Venus Swim" *venus-swim-catalog*))

;;; Stuhrling Original

(defparameter *stuhrling-original-catalog*
  (merge-pathnames "../../data/stuhrling-original/impact-format/Updated-stuhrling-original_IR.txt"
		    *catalogs-dir*))

(defun load-stuhrling-original ()
  (load-catalog "Stuhrling Original" *stuhrling-original-catalog*))

;;; Whiskey Darling

(defparameter *whiskey-darling-catalog*
  (merge-pathnames "../../data/whiskey-darling/impact-format/Updated-whiskey-darling_IR.txt"
		    *catalogs-dir*))

(defun load-whiskey-darling ()
  (load-catalog "Whiskey Darling" *whiskey-darling-catalog*))

;;; RVCA

(defparameter *rvca-catalog*
  (merge-pathnames "../../data/rvca/impact-format/Updated-rvca_IR.txt"
		    *catalogs-dir*))

(defun load-rvca ()
  (load-catalog "RVCA" *rvca-catalog*))

;;; GOLF Partner

(defparameter *golf-partner-catalog*
  (merge-pathnames "../../data/golf-partner/impact-format/Updated-golf-partner_IR.txt"
		    *catalogs-dir*))

(defun load-golf-partner ()
  (load-catalog "GOLF Partner" *golf-partner-catalog*))

;;; Brxl

(defparameter *brxl-catalog*
  (merge-pathnames "../../data/brxl/impact-format/Updated-brxl_IR.txt"
		    *catalogs-dir*))

(defun load-brxl ()
  (load-catalog "Brxl" *brxl-catalog*))

;;; ArtZ Miami

(defparameter *artz-miami-catalog*
  (merge-pathnames "../../data/artz-miami/impact-format/Updated-artz-miami_IR.txt"
		    *catalogs-dir*))

(defun load-artz-miami ()
  (load-catalog "ArtZ Miami" *artz-miami-catalog*))

;;; SELFWHO

(defparameter *selfwho-catalog*
  (merge-pathnames "../../data/selfwho/impact-format/Updated-selfwho_IR.txt"
		    *catalogs-dir*))

(defun load-selfwho ()
  (load-catalog "SELFWHO" *selfwho-catalog*))

;;; Alorair

(defparameter *alorair-catalog*
  (merge-pathnames "../../data/alorair/impact-format/Updated-alorair_IR.txt"
		    *catalogs-dir*))

(defun load-alorair ()
  (load-catalog "Alorair" *alorair-catalog*))

;;; Tetote Home

(defparameter *tetote-home-catalog*
  (merge-pathnames "../../data/tetote-home/impact-format/Updated-tetote-home_IR.txt"
		    *catalogs-dir*))

(defun load-tetote-home ()
  (load-catalog "Tetote Home" *tetote-home-catalog*))

;;; Easecoo

(defparameter *easecoo-catalog*
  (merge-pathnames "../../data/easecoo/impact-format/Updated-easecoo_IR.txt"
		    *catalogs-dir*))

(defun load-easecoo ()
  (load-catalog "Easecoo" *easecoo-catalog*))

;;; RedTop

(defparameter *redtop-catalog*
  (merge-pathnames "../../data/redtop/impact-format/Updated-redtop_IR.txt"
		    *catalogs-dir*))

(defun load-redtop ()
  (load-catalog "RedTop" *redtop-catalog*))

;;; Magic John

(defparameter *magic-john-catalog*
  (merge-pathnames "../../data/magic-john/impact-format/Updated-magic-john_IR.txt"
		    *catalogs-dir*))

(defun load-magic-john ()
  (load-catalog "Magic John" *magic-john-catalog*))

;;; Tuttiosport

(defparameter *tuttiosport-catalog*
  (merge-pathnames "../../data/tuttiosport/impact-format/Updated-tuttiosport_IR.txt"
		    *catalogs-dir*))

(defun load-tuttiosport ()
  (load-catalog "Tuttiosport" *tuttiosport-catalog*))

;;; Rave Sports

(defparameter *rave-sports-catalog*
  (merge-pathnames "../../data/rave-sports/impact-format/Updated-rave-sports_IR.txt"
		    *catalogs-dir*))

(defun load-rave-sports ()
  (load-catalog "Rave Sports" *rave-sports-catalog*))

;;; Belela

(defparameter *belela-catalog*
  (merge-pathnames "../../data/belela/impact-format/Updated-belela_IR.txt"
		    *catalogs-dir*))

(defun load-belela ()
  (load-catalog "Belela" *belela-catalog*))

;;; EGOHOME Mattress

(defparameter *egohome-mattress-catalog*
  (merge-pathnames "../../data/egohome-mattress/impact-format/Updated-egohome-mattress_IR.txt"
		    *catalogs-dir*))

(defun load-egohome-mattress ()
  (load-catalog "EGOHOME Mattress" *egohome-mattress-catalog*))

;;; OutIn

(defparameter *outin-catalog*
  (merge-pathnames "../../data/outin/impact-format/Updated-outin_IR.txt"
		    *catalogs-dir*))

(defun load-outin ()
  (load-catalog "OutIn" *outin-catalog*))

;;; AOOCCI International

(defparameter *aoocci-international-catalog*
  (merge-pathnames "../../data/aoocci-international/impact-format/Updated-aoocci-international_IR.txt"
		    *catalogs-dir*))

(defun load-aoocci-international ()
  (load-catalog "AOOCCI International" *aoocci-international-catalog*))

;;; GoldClub Direct

(defparameter *goldclub-direct-catalog*
  (merge-pathnames "../../data/goldclub-direct/impact-format/Updated-goldclub-direct_IR.txt"
		    *catalogs-dir*))

(defun load-goldclub-direct ()
  (load-catalog "GoldClub Direct" *goldclub-direct-catalog*))

;;; Haoqiebike

(defparameter *haoqiebike-catalog*
  (merge-pathnames "../../data/haoqiebike/impact-format/Updated-haoqiebike_IR.txt"
		    *catalogs-dir*))

(defun load-haoqiebike ()
  (load-catalog "Haoqiebike" *haoqiebike-catalog*))

;;; Screaming O

(defparameter *screaming-o-catalog*
  (merge-pathnames "../../data/screaming-o/impact-format/Updated-screaming-o_IR.txt"
		    *catalogs-dir*))

(defun load-screaming-o ()
  (load-catalog "Screaming O" *screaming-o-catalog*))

;;; Tisscare

(defparameter *tisscare-catalog*
  (merge-pathnames "../../data/tisscare/impact-format/Updated-tisscare_IR.txt"
		    *catalogs-dir*))

(defun load-tisscare ()
  (load-catalog "Tisscare" *tisscare-catalog*))

;;; Plantifique

(defparameter *plantifique-catalog*
  (merge-pathnames "../../data/plantifique/impact-format/Updated-plantifique_IR.txt"
		    *catalogs-dir*))

(defun load-plantifique ()
  (load-catalog "Plantifique" *plantifique-catalog*))

;;; Dreame Yardcare

(defparameter *dreame-yardcare-catalog*
  (merge-pathnames "../../data/dreame-yardcare/impact-format/Updated-dreame-yardcare_IR.txt"
		    *catalogs-dir*))

(defun load-dreame-yardcare ()
  (load-catalog "Dreame Yardcare" *dreame-yardcare-catalog*))

;;; HK Beirui Trade

(defparameter *hk-beirui-trade-catalog*
  (merge-pathnames "../../data/hk-beirui-trade/impact-format/Updated-hk-beirui-trade_IR.txt"
		    *catalogs-dir*))

(defun load-hk-beirui-trade ()
  (load-catalog "HK Beirui Trade" *hk-beirui-trade-catalog*))

;;; SunnyFeel

(defparameter *sunnyfeel-catalog*
  (merge-pathnames "../../data/sunnyfeel/impact-format/Updated-sunnyfeel_IR.txt"
		    *catalogs-dir*))

(defun load-sunnyfeel ()
  (load-catalog "SunnyFeel" *sunnyfeel-catalog*))

;;; Upartner Technology

(defparameter *upartner-technology-catalog*
  (merge-pathnames "../../data/upartner-technology/impact-format/Updated-upartner-technology_IR.txt"
		    *catalogs-dir*))

(defun load-upartner-technology ()
  (load-catalog "Upartner Technology" *upartner-technology-catalog*))

;;; XTEINK

(defparameter *xteink-catalog*
  (merge-pathnames "../../data/xteink/impact-format/Updated-xteink_IR.txt"
		    *catalogs-dir*))

(defun load-xteink ()
  (load-catalog "XTEINK" *xteink-catalog*))

;;; Jiehua International Trade

(defparameter *jiehua-international-catalog*
  (merge-pathnames "../../data/jiehua-international/impact-format/Updated-jiehua-international_IR.txt"
		    *catalogs-dir*))

(defun load-jiehua-international ()
  (load-catalog "Jiehua International Trade" *jiehua-international-catalog*))

;;; Fatboy Hair

(defparameter *fatboy-hair-catalog*
  (merge-pathnames "../../data/fatboy-hair/impact-format/Updated-fatboy-hair_IR.txt"
		    *catalogs-dir*))

(defun load-fatboy-hair ()
  (load-catalog "Fatboy Hair" *fatboy-hair-catalog*))

;;; Packed with Purpose

(defparameter *packed-with-purpose-catalog*
  (merge-pathnames "../../data/packed-with-purpose/impact-format/Updated-packed-with-purpose_IR.txt"
		    *catalogs-dir*))

(defun load-packed-with-purpose ()
  (load-catalog "Packed with Purpose" *packed-with-purpose-catalog*))

;;; RunStar

(defparameter *runstar-catalog*
  (merge-pathnames "../../data/runstar/impact-format/Updated-runstar_IR.txt"
		    *catalogs-dir*))

(defun load-runstar ()
  (load-catalog "RunStar" *runstar-catalog*))

;;; Lilypad Paint

(defparameter *lilypad-paint-catalog*
  (merge-pathnames "../../data/lilypad-paint/impact-format/Updated-lilypad-paint_IR.txt"
		    *catalogs-dir*))

(defun load-lilypad-paint ()
  (load-catalog "Lilypad Paint" *lilypad-paint-catalog*))

;;; Aniioki eBikes

(defparameter *aniioki-ebikes-catalog*
  (merge-pathnames "../../data/aniioki-ebikes/impact-format/Updated-aniioki-ebikes_IR.txt"
		    *catalogs-dir*))

(defun load-aniioki-ebikes ()
  (load-catalog "Aniioki eBikes" *aniioki-ebikes-catalog*))

;;; NuMe

(defparameter *nume-catalog*
  (merge-pathnames "../../data/nume/impact-format/Updated-nume_IR.txt"
		    *catalogs-dir*))

(defun load-nume ()
  (load-catalog "NuMe" *nume-catalog*))

;;; Chef iQ

(defparameter *chef-iq-catalog*
  (merge-pathnames "../../data/chef-iq/impact-format/Updated-chef-iq_IR.txt"
		    *catalogs-dir*))

(defun load-chef-iq ()
  (load-catalog "Chef iQ" *chef-iq-catalog*))

;;; WiiM

(defparameter *wiim-catalog*
  (merge-pathnames "../../data/wiim/impact-format/Updated-wiim_IR.txt"
		    *catalogs-dir*))

(defun load-wiim ()
  (load-catalog "WiiM" *wiim-catalog*))

;;; Aigerri

(defparameter *aigerri-catalog*
  (merge-pathnames "../../data/aigerri/impact-format/Updated-aigerri_IR.txt"
		    *catalogs-dir*))

(defun load-aigerri ()
  (load-catalog "Aigerri" *aigerri-catalog*))

;;; Example Retailer

(defparameter *example-retailer-catalog*
  (merge-pathnames "../../data/example-retailer/impact-format/Updated-example-retailer_IR.txt"
		    *catalogs-dir*))

(defun load-example-retailer ()
  (load-catalog "Example Retailer" *example-retailer-catalog*))

;;; Smart Fuel

(defparameter *smart-fuel-catalog*
  (merge-pathnames "../../data/smart-fuel/impact-format/Updated-smart-fuel_IR.txt"
		    *catalogs-dir*))

(defun load-smart-fuel ()
  (load-catalog "Smart Fuel" *smart-fuel-catalog*))

;;; Signal Ring

(defparameter *signal-ring-catalog*
  (merge-pathnames "../../data/signal-ring/impact-format/Updated-signal-ring_IR.txt"
		    *catalogs-dir*))

(defun load-signal-ring ()
  (load-catalog "Signal Ring" *signal-ring-catalog*))


;;; load-all-generic-catalogs : nil -> nil
;;; Convenience for loading every retailer in this file in one call --
;;; handy for a manual full-refresh from the REPL. The cron script
;;; calls the individual load-* functions directly instead, so it can
;;; skip a retailer whose catalog didn't actually change that day.

(defun load-all-generic-catalogs ()
  (load-sinocrafted)
  (load-terra)
  (load-arcn-home)
  (load-anran)
  (load-dr-jojo-vitamins)
  (load-varla-amazon)
  (load-dowan)
  (load-dnt-optics)
  (load-margovil)
  (load-venus-swim)
  (load-stuhrling-original)
  (load-whiskey-darling)
  (load-rvca)
  (load-golf-partner)
  (load-brxl)
  (load-artz-miami)
  (load-selfwho)
  (load-alorair)
  (load-tetote-home)
  (load-easecoo)
  (load-redtop)
  (load-magic-john)
  (load-tuttiosport)
  (load-rave-sports)
  (load-belela)
  (load-egohome-mattress)
  (load-outin)
  (load-aoocci-international)
  (load-goldclub-direct)
  (load-haoqiebike)
  (load-screaming-o)
  (load-tisscare)
  (load-plantifique)
  (load-dreame-yardcare)
  (load-hk-beirui-trade)
  (load-sunnyfeel)
  (load-upartner-technology)
  (load-xteink)
  (load-jiehua-international)
  (load-fatboy-hair)
  (load-packed-with-purpose)
  (load-runstar)
  (load-lilypad-paint)
  (load-aniioki-ebikes)
  (load-nume)
  (load-chef-iq)
  (load-wiim)
  (load-aigerri)
  (load-example-retailer)
  (load-smart-fuel)
  (load-signal-ring)
  nil)
