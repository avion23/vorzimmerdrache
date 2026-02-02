        // Form submission with inline feedback
        document.getElementById('contactForm').addEventListener('submit', function(e) {
            e.preventDefault();
            const btn = this.querySelector('.submit-btn');
            const feedback = document.getElementById('formFeedback');
            const originalText = btn.textContent;

            // Validate consent checkbox
            const consent = this.querySelector('input[name="consent"]');
            if (!consent.checked) {
                feedback.innerHTML = '<div style="background: #fee2e2; color: #991b1b; padding: 1rem; border-radius: 4px;">Bitte stimmen Sie der Datenverarbeitung zu, damit wir Sie kontaktieren können.</div>';
                return;
            }

            btn.textContent = 'Wird gesendet...';
            btn.disabled = true;

            // Simulate form submission (replace with actual endpoint)
            setTimeout(() => {
                feedback.innerHTML = '<div style="background: #d1fae5; color: #065f46; padding: 1rem; border-radius: 4px;">✓ Vielen Dank! Wir melden uns innerhalb von 24 Stunden bei Ihnen. Checken Sie auch Ihren Spam-Ordner.</div>';
                this.reset();
                btn.textContent = originalText;
                btn.disabled = false;
            }, 1500);
        });

        // ROI Calculator function
        function calculateROI() {
            const anfragen = parseInt(document.getElementById('anfragen').value) || 0;
            const verpasst = parseInt(document.getElementById('verpasst').value) || 0;
            const auftragswert = parseInt(document.getElementById('auftragswert').value) || 0;

            // Calculate
            const verpassteAnfragen = Math.round(anfragen * (verpasst / 100));
            const verloreneAuftraege = Math.round(verpassteAnfragen * 0.7); // 70% conversion rate
            const umsatzverlust = verloreneAuftraege * auftragswert * 4.3; // 4.3 weeks per month
            const geretteterUmsatz = umsatzverlust * 0.8; // 80% saved

            // Update display
            document.getElementById('verpassteAnfragen').textContent = verpassteAnfragen;
            document.getElementById('verloreneAuftraege').textContent = verloreneAuftraege;
            document.getElementById('umsatzverlust').textContent = '€' + umsatzverlust.toLocaleString();
            document.getElementById('geretteterUmsatz').textContent = '€' + geretteterUmsatz.toLocaleString();
        }

        // Calculate on load
        document.addEventListener('DOMContentLoaded', function() {
            calculateROI();
            if (!localStorage.getItem('cookiesAccepted')) {
                document.getElementById('cookieBanner').classList.add('show');
            }
        });

        function acceptCookies() {
            document.getElementById('cookieBanner').classList.remove('show');
            localStorage.setItem('cookiesAccepted', 'true');
        }

        // Check if cookies already accepted
        if (localStorage.getItem('cookiesAccepted') === 'true') {
            document.getElementById('cookieBanner').style.display = 'none';
        }
