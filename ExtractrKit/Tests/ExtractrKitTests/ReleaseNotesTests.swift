import Foundation
import Testing

@testable import ExtractrKit

@Suite struct ReleaseNotesTests {
    @Test func parsesHeadingsBulletsAndParagraphs() {
        let body = """
            ## What's new
            - Waveform trimmer
            - Speed control

            Trimming is now whole seconds.
            """
        #expect(
            ReleaseNotes.blocks(from: body) == [
                .heading(level: 2, text: "What's new"),
                .bullet("Waveform trimmer"),
                .bullet("Speed control"),
                .paragraph("Trimming is now whole seconds."),
            ])
    }

    @Test func joinsWrappedParagraphsAndBullets() {
        let body = """
            A long sentence
            wrapped over lines.

            - A bullet that
              wraps too
            """
        #expect(
            ReleaseNotes.blocks(from: body) == [
                .paragraph("A long sentence wrapped over lines."),
                .bullet("A bullet that wraps too"),
            ])
    }

    @Test func dropsInstallSectionAndRequirementLine() {
        let body = """
            ## What's new
            - Update window

            **Requires macOS 26 or later.**

            ## Install
            Download the DMG and drag it to Applications.

            ### Unsigned build
            Run xattr.

            ## Thanks
            - Everyone
            """
        #expect(
            ReleaseNotes.blocks(from: body) == [
                .heading(level: 2, text: "What's new"),
                .bullet("Update window"),
                .heading(level: 2, text: "Thanks"),
                .bullet("Everyone"),
            ])
    }

    @Test func asteriskBulletsAndNonHeadingHashes() {
        let body = """
            * Starred bullet
            #notaheading
            """
        #expect(
            ReleaseNotes.blocks(from: body) == [
                .bullet("Starred bullet"),
                .paragraph("#notaheading"),
            ])
    }

    @Test func emptyBodyProducesNoBlocks() {
        #expect(ReleaseNotes.blocks(from: "").isEmpty)
        #expect(ReleaseNotes.blocks(from: "\n\n  \n").isEmpty)
    }

    @Test func normalizesWindowsLineEndings() {
        #expect(
            ReleaseNotes.blocks(from: "# Title\r\n- One\r\n") == [
                .heading(level: 1, text: "Title"),
                .bullet("One"),
            ])
    }

    /// Real release shape: the install heading carries a parenthetical, and the
    /// walkthrough plus the DMG checksum trail behind it.
    @Test func dropsInstallSectionWithParentheticalHeading() {
        let body = """
            Hosts Switchr now speaks French and Spanish.

            ## What's new

            - **Four languages.** English (US and UK), French and Spanish.
            - **Everything is translated, not just the buttons.** The views and the whole Help window.

            French and Spanish haven't had a native-speaker pass yet.

            ## Install (unsigned app)

            Hosts Switchr uses no Apple Developer Program, so macOS blocks it on first launch:

            1. Double-click **Hosts Switchr**; when macOS says it "can't verify the developer," click **Done**.
            2. Open **System Settings → Privacy & Security** and click **Open Anyway**.
            3. Authenticate and click **Open**. macOS only asks once.

            Updating from 0.2.4 or later? The in-app updater handles this for you.

            **Requires macOS 26 (Tahoe) or later · Apple Silicon**.

            **DMG SHA-256**
            `054d9e5f29add4a6e3f1f1d45905b5e1242b9015a5ecc7cccf1c18544975f5ee`
            """
        #expect(
            ReleaseNotes.blocks(from: body) == [
                .paragraph("Hosts Switchr now speaks French and Spanish."),
                .heading(level: 2, text: "What's new"),
                .bullet("**Four languages.** English (US and UK), French and Spanish."),
                .bullet("**Everything is translated, not just the buttons.** The views and the whole Help window."),
                .paragraph("French and Spanish haven't had a native-speaker pass yet."),
            ])
    }

    @Test func dropsInstallationAndInstallingHeadings() {
        let body = """
            ## Installation
            Drag it to Applications.

            ## Installing from source
            Clone and build.

            ## Thanks
            - Everyone
            """
        #expect(
            ReleaseNotes.blocks(from: body) == [
                .heading(level: 2, text: "Thanks"),
                .bullet("Everyone"),
            ])
    }

    /// Both real forms: the whole line bolded, and only the version bolded.
    @Test func dropsRequirementLineWhereverEmphasisFalls() {
        let body = """
            Smarter change tracking, a Cancel button, and a clearer fragment editor.

            **Requires macOS 26 (Tahoe) or later.**

            Requires **macOS 26 (Tahoe) or later · Apple Silicon**.

            ## New
            - **Cancel button.**
            """
        #expect(
            ReleaseNotes.blocks(from: body) == [
                .paragraph("Smarter change tracking, a Cancel button, and a clearer fragment editor."),
                .heading(level: 2, text: "New"),
                .bullet("**Cancel button.**"),
            ])
    }

    @Test func dropsThematicBreaks() {
        let body = """
            Smarter change tracking, a Cancel button, and a clearer fragment editor.

            ---

            ## New
            - **Cancel button.**

            * * *

            ## Improved
            - Toggle rows dim their label when off.
            """
        #expect(
            ReleaseNotes.blocks(from: body) == [
                .paragraph("Smarter change tracking, a Cancel button, and a clearer fragment editor."),
                .heading(level: 2, text: "New"),
                .bullet("**Cancel button.**"),
                .heading(level: 2, text: "Improved"),
                .bullet("Toggle rows dim their label when off."),
            ])
    }
}
