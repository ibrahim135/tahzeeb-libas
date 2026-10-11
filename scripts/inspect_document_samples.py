#!/usr/bin/env python3
"""Optional independent Poppler checks for synthetic Phase 5 test PDFs."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else pathlib.Path('/tmp/tahzeeb-pdf-samples')


def extract(name):
    return subprocess.run(['pdftotext', '-layout', str(root / name), '-'],
                          check=True, capture_output=True, text=True).stdout


for kind, label in [('receipt', 'Payment receipt'), ('warehouse', 'Warehouse measurement slip')]:
    for copy, copy_label in [('original', 'Customer copy' if kind == 'receipt' else 'Warehouse copy'),
                             ('shop', 'Shop copy')]:
        name = f'{kind}_{copy}.pdf'
        text = extract(name)
        assert label in text and copy_label in text, name
        for required in ['Tahzeeb Libas', 'Bill: 0007', 'Phone: 0012345678', '10/01/2025',
                         'Suit / 3-piece - Quantity: 2']:
            assert required in text, (name, required)
        if kind == 'receipt':
            for required in ['Rate: ₹123.45', 'Amount: ₹246.90', 'Subtotal: ₹647.90',
                             'Discount: ₹0.75', 'Order total: ₹647.15', 'Received: ₹50.25',
                             'Balance: ₹596.90', '02/01/2025 - ₹50.25 - Cash', 'Partially paid']:
                assert required in text, (name, required)
            assert '₹98.76' not in text, name  # Original corrected amount.
        else:
            for forbidden in ['₹', '123.45', '647.15', '50.25', '596.90', 'Historic bill',
                              'Private shop receipt note', 'Private payment note', 'Test notes',
                              'Test address', 'Discount:', 'Received:', 'Balance:', 'Payment status:']:
                assert forbidden not in text, (name, forbidden)
            for required in ['Upper body - inches', 'Lower body - inches', 'Length: 30.125',
                             'Length: 42.75', 'Hips: 40', 'Hips: 41.5', 'Alter sleeves',
                             'No standard body measurements.', 'No measurements entered.']:
                assert required in text, (name, required)
        info = subprocess.run(['pdfinfo', str(root / name)], check=True,
                              capture_output=True, text=True).stdout
        assert '(A4)' in info and 'JavaScript:      no' in info, name

long_text = extract('warehouse_long.pdf')
assert {int(i) for i in re.findall(r'Instruction (\d+):', long_text)} == set(range(800))
assert ''.join(long_text.split()).count('LONGTOKEN') == 200
assert 'FINAL_WAREHOUSE_INSTRUCTION' in long_text
assert '₹' not in long_text
print('PDF extraction passed: both formats/copy labels, exact INR totals, warehouse privacy, A4, and all long-slip instructions.')
