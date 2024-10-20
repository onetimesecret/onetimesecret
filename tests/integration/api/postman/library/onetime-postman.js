/**
 * Postman Package Library - Onetime
 *
 * Add commonly used scripts and tests to your team's Package Library. Use
 * JavaScript code, and export functions with module.exports for reuse in
 * pre-request and post-response scripts.
 *
 *
 * Usage:
 *
 * const onetimePostman = pm.require('@SUBDOMAIN/onetime-postman');
 * onetimePostman.isSuccess(request, response);
 *
 * @see https://learning.postman.com/docs/tests-and-scripts/write-scripts/package-library/
 * @see https://learning.postman.com/docs/tests-and-scripts/write-scripts/postman-sandbox-api-reference/
 * @see https://learning.postman.com/docs/tests-and-scripts/write-scripts/variables-list/
 */

/* Set a request variable */
// pm.variables.set("newShrimp", jsonData.shrimp);

function isSuccess(request, response) {
    return request.method == 'get' && response.status == 200;
}

function addShrimp(request, response) {
    const shrimp = pm.collectionVariables.get("shrimp");

    if (shrimp) {
        console.log("[pre-request] Adding shrimp header")
        pm.request.headers.add({
            key: "O-Shrimp",
            value: shrimp
        });
    }

    return shrimp;
}

function logger(data) {
    console.log(`[INFO], ${data}`)
}

module.exports = {
    addShrimp,
    isSuccess,
    logger
}
